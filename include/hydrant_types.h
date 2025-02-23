// include/hydrant_types.h

#ifndef HYDRANT_TYPES_H
#define HYDRANT_TYPES_H

#include "hydrant.h"

typedef enum {
  CONN_AVAILABLE,
  CONN_IN_USE,
  CONN_DEAD,
  CONN_PERMANENT_FAILURE
} ConnectionState;

typedef struct PoolConnection {
  PGconn *conn;
  ConnectionState state;
  time_t last_used;
  int failed_attempts;
  int recovery_attempts;
  time_t next_recovery_attempt;
  char last_error[MAX_ERROR_LENGTH];
} PoolConnection;

typedef struct BatchStats {
  size_t processed;
  size_t failed;
  time_t timestamp;
} BatchStats;

typedef struct HydrantConfig {
  char *db_conn_string;
  size_t batch_size;
  int max_retries;
  int retry_delay_ms;
  bool require_ssl;
} HydrantConfig;

typedef struct WorkerThread {
  HydrantContext *ctx;
  bool running;
  pthread_t thread;
} WorkerThread;

typedef struct HydrantContext {
  HydrantConfig *config;
  atomic_bool shutdown_requested;

  // Connection pool
  PoolConnection pool[MAX_POOL_SIZE];
  size_t healthy_connections;
  pthread_mutex_t pool_mutex;
  pthread_cond_t pool_cond;

  // Batch processing
  char *batch_buffer;
  size_t current_batch_pos;
  pthread_mutex_t batch_mutex;
  BatchStats *batch_stats;
  size_t batch_stats_size;
  size_t current_batch;

  // Workers
  WorkerThread *workers;
  size_t worker_count;

  // Stats and monitoring
  struct {
    size_t total_bytes;
    size_t batches_processed;
    size_t copy_operations;
    size_t errors;
    size_t connection_resets;
    size_t connection_failures;
    double avg_batch_time_ms;
    time_t start_time;
    time_t last_batch;
  } stats;
  pthread_mutex_t stats_mutex;

  char source_id[37];
} HydrantContext;

#endif // HYDRANT_TYPES_H
