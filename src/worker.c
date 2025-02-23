// src/worker.c

#include <errno.h>
#include <string.h>
#include <unistd.h>

#include "hydrant.h"
#include "hydrant_types.h"

void *worker_thread(void *arg) {
  WorkerThread *worker = (WorkerThread *)arg;
  HydrantContext *ctx = worker->ctx;

  while (!atomic_load(&ctx->shutdown_requested)) {
    pthread_mutex_lock(&ctx->stats_mutex);

    // Update monitoring stats
    time_t now = time(NULL);
    if (now - ctx->stats.last_batch > 60) { // Report every minute
      structured_log("INFO", "Worker status: processed %zu batches, %zu errors",
                     ctx->stats.batches_processed, ctx->stats.errors);
      ctx->stats.last_batch = now;
    }

    // Check pool health
    pthread_mutex_lock(&ctx->pool_mutex);
    size_t available = 0, dead = 0;
    for (int i = 0; i < MAX_POOL_SIZE; i++) {
      switch (ctx->pool[i].state) {
      case CONN_AVAILABLE:
        available++;
        break;
      case CONN_DEAD:
      case CONN_PERMANENT_FAILURE:
        dead++;
        break;
      default:
        break;
      }
    }

    if (dead > 0 && available < MAX_POOL_SIZE / 2) {
      structured_log("WARN", "Pool health degraded: %zu dead, %zu available",
                     dead, available);
    }

    pthread_mutex_unlock(&ctx->pool_mutex);
    pthread_mutex_unlock(&ctx->stats_mutex);

    sleep(1);
  }

  structured_log("INFO", "Worker thread shutting down");
  return NULL;
}

bool start_workers(HydrantContext *ctx, size_t num_workers) {
  ctx->workers = calloc(num_workers, sizeof(WorkerThread));
  if (!ctx->workers) {
    structured_log("ERROR", "Failed to allocate worker array: %s",
                   strerror(errno));
    return false;
  }

  ctx->worker_count = num_workers;

  for (size_t i = 0; i < num_workers; i++) {
    WorkerThread *worker = &ctx->workers[i];
    worker->ctx = ctx;
    worker->running = true;

    if (pthread_create(&worker->thread, NULL, worker_thread, worker) != 0) {
      structured_log("ERROR", "Failed to create worker thread %zu: %s", i,
                     strerror(errno));
      worker->running = false;
      return false;
    }
  }

  return true;
}

void stop_workers(HydrantContext *ctx) {
  atomic_store(&ctx->shutdown_requested, true);

  for (size_t i = 0; i < ctx->worker_count; i++) {
    WorkerThread *worker = &ctx->workers[i];
    if (worker->running) {
      pthread_join(worker->thread, NULL);
      worker->running = false;
    }
  }

  free(ctx->workers);
  ctx->workers = NULL;
  ctx->worker_count = 0;
}
