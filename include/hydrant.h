// include/hydrant.h

#ifndef HYDRANT_H
#define HYDRANT_H

#include <postgresql/libpq-fe.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

#define MAX_RECOVERY_ATTEMPTS 3
#define CONNECTION_DEAD_THRESHOLD 5
#define MAX_BACKOFF_ATTEMPTS 10
#define MAX_POOL_SIZE 10

#define RECOVERY_BACKOFF_BASE_MS 100

#define MAX_ERROR_LENGTH (1 * 1024)          //  1KB
#define MAX_STATUS_LENGTH (4 * 1024)         //  4KB
#define COPY_CHUNK_SIZE (8 * 1024)           //  8KB
#define MIN_BATCH_SIZE (64 * 1024)           // 64KB
#define DEFAULT_BATCH_SIZE (1 * 1024 * 1024) //  1MB
#define MAX_BATCH_SIZE (10 * 1024 * 1024)    // 10MB

typedef struct HydrantContext HydrantContext;
typedef struct HydrantConfig HydrantConfig;
typedef struct WorkerThread WorkerThread;
typedef struct PoolConnection PoolConnection;

/**
 *
 * @param
 * @return
 */
PGconn *get_connection(HydrantContext *ctx);

/**
 *
 * @param
 * @return
 */
PoolConnection *find_pool_connection(HydrantContext *ctx, PGconn *conn);

/**
 *
 * @param
 * @return
 */
void mark_connection_dead(HydrantContext *ctx, PoolConnection *pc,
                          const char *error);

/**
 *
 * @param
 * @return
 */
void return_connection(HydrantContext *ctx, PGconn *conn, bool had_error);

/**
 * Initialize the hydrant system
 * @param config_path Path to YAML config file, or NULL for env vars
 * @return Initialized context or NULL on error
 */
HydrantContext *init_hydrant(const char *config_path);

/**
 * Request graceful shutdown of the hydrant
 * @param ctx The hydrant context
 */
void request_shutdown(HydrantContext *ctx);

/**
 * Add data to the current batch
 * @param ctx The hydrant context
 * @param data Pointer to data
 * @param size Size of data
 * @return true if added, false if batch is full
 */
bool add_to_batch(HydrantContext *ctx, const char *data, size_t size);

/**
 * Flush the current batch to the database
 * @param ctx The hydrant context
 * @param processed Number of bytes successfully processed
 * @param failed Number of bytes that failed to process
 * @return true on success, false on error
 */
bool flush_batch(HydrantContext *ctx, size_t *processed, size_t *failed);

/**
 * Get detailed status of the hydrant system
 * @param ctx The hydrant context
 * @return JSON string containing status (caller must free)
 */
char *get_detailed_status(HydrantContext *ctx);

/**
 * Thread-safe structured logging
 * @param level Log level ("ERROR", "WARN", "INFO", "DEBUG")
 * @param format Printf-style format string
 */
void structured_log(const char *level, const char *format, ...);

/**
 * Start worker threads
 * @param ctx The hydrant context
 * @param num_workers Number of worker threads to start
 * @return true on success, false on error
 */
bool start_workers(HydrantContext *ctx, size_t num_workers);

/**
 * Stop all worker threads
 * @param ctx The hydrant context
 */
void stop_workers(HydrantContext *ctx);

/**
 *
 * @param
 * @return
 */
void update_batch_stats(HydrantContext *ctx, size_t processed, size_t failed);

/**
 *
 * @param
 * @return
 */
void process_input(HydrantContext *ctx);

#endif // HYDRANT_H
