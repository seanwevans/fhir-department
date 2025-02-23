// src/connection.c

#include <errno.h>
#include <string.h>
#include <unistd.h>

#include "hydrant.h"
#include "hydrant_types.h"

PoolConnection *find_pool_connection(HydrantContext *ctx, PGconn *conn) {
  for (int i = 0; i < MAX_POOL_SIZE; i++) {
    if (ctx->pool[i].conn == conn) {
      return &ctx->pool[i];
    }
  }
  return NULL;
}

void mark_connection_dead(HydrantContext *ctx, PoolConnection *pc,
                          const char *error) {
  pthread_mutex_lock(&ctx->stats_mutex);
  pthread_mutex_lock(&ctx->pool_mutex);

  if (pc->state != CONN_DEAD && pc->state != CONN_PERMANENT_FAILURE) {
    ctx->healthy_connections--;
    pc->state = CONN_DEAD;
    snprintf(pc->last_error, MAX_ERROR_LENGTH, "%s", error);
    structured_log("WARN", "Connection marked dead: %s", error);
  }

  pthread_mutex_unlock(&ctx->pool_mutex);
  pthread_mutex_unlock(&ctx->stats_mutex);
}

bool recover_dead_connection(HydrantContext *ctx, PoolConnection *pc) {
  time_t now = time(NULL);

  if (now < pc->next_recovery_attempt) {
    return false;
  }

  if (pc->recovery_attempts >= MAX_RECOVERY_ATTEMPTS) {
    if (pc->state != CONN_PERMANENT_FAILURE) {
      structured_log("ERROR",
                     "Connection permanently failed after %d recovery "
                     "attempts. Last error: %s",
                     pc->recovery_attempts, pc->last_error);
      pc->state = CONN_PERMANENT_FAILURE;
    }
    return false;
  }

  structured_log("INFO", "Attempting to recover connection (attempt %d/%d)",
                 pc->recovery_attempts + 1, MAX_RECOVERY_ATTEMPTS);

  if (pc->conn) {
    PQfinish(pc->conn);
  }

  pc->conn = PQconnectdb(ctx->config->db_conn_string);
  if (PQstatus(pc->conn) != CONNECTION_OK) {
    pc->recovery_attempts++;
    snprintf(pc->last_error, MAX_ERROR_LENGTH, "Recovery failed: %s",
             PQerrorMessage(pc->conn));

    pc->next_recovery_attempt =
        now + (RECOVERY_BACKOFF_BASE_MS
               << (pc->recovery_attempts < MAX_BACKOFF_ATTEMPTS
                       ? pc->recovery_attempts
                       : MAX_BACKOFF_ATTEMPTS)) /
                  1000;

    pthread_mutex_lock(&ctx->stats_mutex);
    ctx->stats.connection_failures++;
    pthread_mutex_unlock(&ctx->stats_mutex);

    return false;
  }

  if (ctx->config->require_ssl && !PQsslInUse(pc->conn)) {
    snprintf(pc->last_error, MAX_ERROR_LENGTH,
             "Recovery failed: SSL required but not in use");
    pc->recovery_attempts++;
    return false;
  }

  PGresult *res = PQprepare(pc->conn, "copy_stmt",
                            "COPY original_copy(source_id, content, seq_num, "
                            "checksum) FROM STDIN WITH (FORMAT binary)",
                            0, NULL);

  if (PQresultStatus(res) != PGRES_COMMAND_OK) {
    snprintf(pc->last_error, MAX_ERROR_LENGTH,
             "Failed to prepare statement: %s", PQerrorMessage(pc->conn));
    PQclear(res);
    pc->recovery_attempts++;
    return false;
  }

  PQclear(res);
  pc->failed_attempts = 0;
  pc->recovery_attempts = 0;
  pc->next_recovery_attempt = 0;
  pc->state = CONN_AVAILABLE;

  pthread_mutex_lock(&ctx->stats_mutex);
  ctx->stats.connection_resets++;
  ctx->healthy_connections++;
  pthread_mutex_unlock(&ctx->stats_mutex);

  structured_log("INFO", "Successfully recovered connection");
  return true;
}

PGconn *get_connection(HydrantContext *ctx) {
  pthread_mutex_lock(&ctx->pool_mutex);

  // First pass: look for available healthy connections
  for (int i = 0; i < MAX_POOL_SIZE; i++) {
    PoolConnection *pc = &ctx->pool[i];
    if (pc->state == CONN_AVAILABLE && PQstatus(pc->conn) == CONNECTION_OK) {

      pc->state = CONN_IN_USE;
      pc->last_used = time(NULL);
      pthread_mutex_unlock(&ctx->pool_mutex);
      return pc->conn;
    }
  }

  // Second pass: try to recover dead connections
  for (int i = 0; i < MAX_POOL_SIZE; i++) {
    PoolConnection *pc = &ctx->pool[i];
    if (pc->state == CONN_DEAD) {
      if (recover_dead_connection(ctx, pc)) {
        pc->state = CONN_IN_USE;
        pc->last_used = time(NULL);
        pthread_mutex_unlock(&ctx->pool_mutex);
        return pc->conn;
      }
    }
  }

  // Wait for a connection to become available
  struct timespec timeout;
  clock_gettime(CLOCK_REALTIME, &timeout);
  timeout.tv_sec += 1;

  while (pthread_cond_timedwait(&ctx->pool_cond, &ctx->pool_mutex, &timeout) !=
         ETIMEDOUT) {
    for (int i = 0; i < MAX_POOL_SIZE; i++) {
      PoolConnection *pc = &ctx->pool[i];
      if (pc->state == CONN_AVAILABLE && PQstatus(pc->conn) == CONNECTION_OK) {

        pc->state = CONN_IN_USE;
        pc->last_used = time(NULL);
        pthread_mutex_unlock(&ctx->pool_mutex);
        return pc->conn;
      }
    }
  }

  pthread_mutex_unlock(&ctx->pool_mutex);
  return NULL;
}

void return_connection(HydrantContext *ctx, PGconn *conn, bool had_error) {
  pthread_mutex_lock(&ctx->pool_mutex);

  PoolConnection *pc = find_pool_connection(ctx, conn);
  if (pc) {
    if (had_error) {
      pc->failed_attempts++;
      snprintf(pc->last_error, MAX_ERROR_LENGTH, "%s", PQerrorMessage(conn));

      if (pc->failed_attempts >= CONNECTION_DEAD_THRESHOLD) {
        mark_connection_dead(ctx, pc, pc->last_error);
      } else {
        pc->state = CONN_AVAILABLE;
      }
    } else {
      pc->state = CONN_AVAILABLE;
      pc->failed_attempts = 0;
    }

    pthread_cond_signal(&ctx->pool_cond);
  }

  pthread_mutex_unlock(&ctx->pool_mutex);
}
