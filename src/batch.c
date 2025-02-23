// src/batch.c

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "hydrant.h"
#include "hydrant_types.h"

bool add_to_batch(HydrantContext *ctx, const char *data, size_t size) {
  pthread_mutex_lock(&ctx->batch_mutex);

  if (ctx->current_batch_pos + size > ctx->config->batch_size) {
    pthread_mutex_unlock(&ctx->batch_mutex);
    return false;
  }

  memcpy(ctx->batch_buffer + ctx->current_batch_pos, data, size);
  ctx->current_batch_pos += size;

  pthread_mutex_unlock(&ctx->batch_mutex);
  return true;
}

bool flush_batch(HydrantContext *ctx, size_t *processed, size_t *failed) {
  if (ctx->current_batch_pos == 0)
    return true;

  PGconn *conn = get_connection(ctx);
  if (!conn) {
    structured_log("ERROR", "No connection available for batch flush");
    return false;
  }

  bool success = true;
  *processed = 0;
  *failed = 0;

  // Begin transaction
  PGresult *res = PQexec(conn, "BEGIN");
  if (PQresultStatus(res) != PGRES_COMMAND_OK) {
    const char *error = PQerrorMessage(conn);
    structured_log("ERROR", "Failed to begin transaction: %s", error);
    PQclear(res);
    mark_connection_dead(ctx, find_pool_connection(ctx, conn), error);
    return false;
  }
  PQclear(res);

  // Start COPY
  res = PQexecPrepared(conn, "copy_stmt", 0, NULL, NULL, NULL, 1);
  if (PQresultStatus(res) != PGRES_COPY_IN) {
    const char *error = PQerrorMessage(conn);
    structured_log("ERROR", "Failed to start COPY: %s", error);
    PQclear(res);
    PQexec(conn, "ROLLBACK");
    mark_connection_dead(ctx, find_pool_connection(ctx, conn), error);
    return false;
  }
  PQclear(res);

  // Chunked write with buffer management
  size_t total_written = 0;
  size_t retry_count = 0;
  const size_t max_retries = 5;

  while (total_written < ctx->current_batch_pos) {
    size_t remaining = ctx->current_batch_pos - total_written;
    size_t chunk_size =
        (remaining > COPY_CHUNK_SIZE) ? COPY_CHUNK_SIZE : remaining;

    // Try to write chunk
    int result =
        PQputCopyData(conn, ctx->batch_buffer + total_written, chunk_size);

    if (result == 1) {
      // Success - chunk written
      total_written += chunk_size;
      retry_count = 0; // Reset retry counter on success

      // Update progress for monitoring
      if (total_written % (1024 * 1024) == 0) { // Log every 1MB
        structured_log("DEBUG", "COPY progress: %zu/%zu bytes", total_written,
                       ctx->current_batch_pos);
      }
    } else if (result == 0) {
      // Buffer full - check if we should wait
      if (!PQisBusy(conn)) {
        PQconsumeInput(conn); // Process any pending data
      }

      retry_count++;
      if (retry_count > max_retries) {
        const char *error = "Max retries exceeded waiting for buffer space";
        structured_log("ERROR", "%s", error);
        mark_connection_dead(ctx, find_pool_connection(ctx, conn), error);
        success = false;
        break;
      }

      // Exponential backoff with max cap
      // usleep(1000 * (1 << (retry_count < MAX_BACKOFF_ATTEMPTS ?
      // retry_count : MAX_BACKOFF_ATTEMPTS)));
      struct timespec ts = {.tv_sec = 0,
                            .tv_nsec = 1000000 *
                                       (1 << (retry_count < MAX_BACKOFF_ATTEMPTS
                                                  ? retry_count
                                                  : MAX_BACKOFF_ATTEMPTS))};
      nanosleep(&ts, NULL);
      continue;
    } else {
      // Error
      const char *error = PQerrorMessage(conn);
      structured_log("ERROR", "Failed to write batch data: %s", error);
      mark_connection_dead(ctx, find_pool_connection(ctx, conn), error);
      success = false;
      break;
    }
  }

  if (success) {
    // End COPY
    if (PQputCopyEnd(conn, NULL) != 1) {
      const char *error = PQerrorMessage(conn);
      structured_log("ERROR", "Failed to end COPY: %s", error);
      success = false;
    } else {
      // Commit transaction
      res = PQexec(conn, "COMMIT");
      if (PQresultStatus(res) != PGRES_COMMAND_OK) {
        const char *error = PQerrorMessage(conn);
        structured_log("ERROR", "Failed to commit transaction: %s", error);
        success = false;
      }
      PQclear(res);
    }
  }

  if (!success) {
    PQexec(conn, "ROLLBACK");
    *failed = ctx->current_batch_pos - total_written;
  }

  *processed = total_written;

  // Update stats under lock
  pthread_mutex_lock(&ctx->stats_mutex);
  ctx->stats.batches_processed++;
  ctx->stats.total_bytes += total_written;
  if (*failed > 0) {
    ctx->stats.errors++;
  }
  pthread_mutex_unlock(&ctx->stats_mutex);

  return_connection(ctx, conn, !success);
  ctx->current_batch_pos = 0;
  return success;
}

void update_batch_stats(HydrantContext *ctx, size_t processed, size_t failed) {
  pthread_mutex_lock(&ctx->stats_mutex);

  // Update current batch stats
  ctx->batch_stats[ctx->current_batch].processed = processed;
  ctx->batch_stats[ctx->current_batch].failed = failed;
  ctx->batch_stats[ctx->current_batch].timestamp = time(NULL);

  // Update running stats
  ctx->stats.total_bytes += processed;
  ctx->stats.batches_processed++;
  ctx->stats.errors += failed;

  // Calculate average batch processing time
  if (ctx->stats.batches_processed > 1) {
    time_t batch_time = ctx->batch_stats[ctx->current_batch].timestamp -
                        ctx->batch_stats[ctx->current_batch - 1].timestamp;
    ctx->stats.avg_batch_time_ms =
        (ctx->stats.avg_batch_time_ms * (ctx->stats.batches_processed - 1) +
         batch_time * 1000.0) /
        ctx->stats.batches_processed;
  }

  ctx->current_batch = (ctx->current_batch + 1) % ctx->batch_stats_size;
  pthread_mutex_unlock(&ctx->stats_mutex);
}

char *get_detailed_status(HydrantContext *ctx) {
  pthread_mutex_lock(&ctx->stats_mutex);
  pthread_mutex_lock(&ctx->pool_mutex);

  char *status = malloc(MAX_STATUS_LENGTH);
  if (!status) {
    pthread_mutex_unlock(&ctx->pool_mutex);
    pthread_mutex_unlock(&ctx->stats_mutex);
    return NULL;
  }

  int available = 0, in_use = 0, dead = 0;
  for (int i = 0; i < MAX_POOL_SIZE; i++) {
    switch (ctx->pool[i].state) {
    case CONN_AVAILABLE:
      available++;
      break;
    case CONN_IN_USE:
      in_use++;
      break;
    case CONN_DEAD:
      dead++;
      break;
    case CONN_PERMANENT_FAILURE:
      dead++;
      break;
    }
  }

  snprintf(status, MAX_STATUS_LENGTH,
           "{"
           "\"uptime_seconds\":%ld,"
           "\"total_bytes\":%zu,"
           "\"batches_processed\":%zu,"
           "\"errors\":%zu,"
           "\"avg_batch_time_ms\":%.2f,"
           "\"connections\":{"
           "\"available\":%d,"
           "\"in_use\":%d,"
           "\"dead\":%d,"
           "\"resets\":%zu,"
           "\"failures\":%zu"
           "},"
           "\"current_batch_size\":%zu"
           "}",
           time(NULL) - ctx->stats.start_time, ctx->stats.total_bytes,
           ctx->stats.batches_processed, ctx->stats.errors,
           ctx->stats.avg_batch_time_ms, available, in_use, dead,
           ctx->stats.connection_resets, ctx->stats.connection_failures,
           ctx->current_batch_pos);

  pthread_mutex_unlock(&ctx->pool_mutex);
  pthread_mutex_unlock(&ctx->stats_mutex);

  return status;
}

void process_input(HydrantContext *ctx) {
  char buffer[ctx->config->batch_size];
  size_t bytes_read;
  struct timespec batch_start, batch_end;

  clock_gettime(CLOCK_MONOTONIC, &batch_start);

  while ((bytes_read = fread(buffer, 1, sizeof(buffer), stdin)) > 0) {
    if (!add_to_batch(ctx, buffer, bytes_read)) {
      // Batch is full, flush it
      size_t processed = 0, failed = 0;
      flush_batch(ctx, &processed, &failed);
      update_batch_stats(ctx, processed, failed);

      // Try adding to the fresh batch
      if (!add_to_batch(ctx, buffer, bytes_read)) {
        structured_log("ERROR", "Failed to add to fresh batch: %s",
                       strerror(errno));
        break;
      }
    }

    if (atomic_load(&ctx->shutdown_requested))
      break;
  }

  // Final batch
  if (ctx->current_batch_pos > 0) {
    size_t processed = 0, failed = 0;
    flush_batch(ctx, &processed, &failed);
    update_batch_stats(ctx, processed, failed);
  }

  clock_gettime(CLOCK_MONOTONIC, &batch_end);
  double batch_time = (batch_end.tv_sec - batch_start.tv_sec) * 1000.0 +
                      (batch_end.tv_nsec - batch_start.tv_nsec) / 1000000.0;

  // Log final stats
  char *final_status = get_detailed_status(ctx);
  structured_log("INFO", "Processing complete in %f sec. Final status: %s",
                 batch_time, final_status);
  free(final_status);
}