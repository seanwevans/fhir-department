// src/init.c

#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <string.h>
#include <unistd.h>
#include <yaml.h>

#include "hydrant.h"
#include "hydrant_types.h"

static HydrantConfig *load_config(const char *config_path) {
  HydrantConfig *config = calloc(1, sizeof(HydrantConfig));
  if (!config)
    return NULL;

  // defaults
  config->batch_size = DEFAULT_BATCH_SIZE;
  config->max_retries = 3;
  config->retry_delay_ms = 100;
  config->require_ssl = true;

  // Use environment variables
  if (!config_path) {
    char *batch_size = getenv("HYDRANT_BATCH_SIZE");
    if (batch_size) {
      size_t size = atol(batch_size);
      if (size >= MIN_BATCH_SIZE && size <= MAX_BATCH_SIZE) {
        config->batch_size = size;
      }
    }

    char *conn_string = getenv("HYDRANT_DB_URL");
    if (conn_string) {
      config->db_conn_string = strdup(conn_string);
    } else {
      structured_log("ERROR", "No database connection string provided");
      free(config);
      return NULL;
    }

    return config;
  }

  // Load from YAML file
  FILE *fh = fopen(config_path, "r");
  if (!fh) {
    structured_log("ERROR", "Failed to open config file: %s", strerror(errno));
    free(config);
    return NULL;
  }

  yaml_parser_t parser;
  yaml_document_t document;

  if (!yaml_parser_initialize(&parser)) {
    structured_log("ERROR", "Failed to initialize YAML parser");
    fclose(fh);
    free(config);
    return NULL;
  }

  yaml_parser_set_input_file(&parser, fh);

  if (!yaml_parser_load(&parser, &document)) {
    structured_log("ERROR", "Failed to parse YAML: %s", parser.problem);
    yaml_parser_delete(&parser);
    fclose(fh);
    free(config);
    return NULL;
  }

  yaml_node_t *root = yaml_document_get_root_node(&document);
  if (!root || root->type != YAML_MAPPING_NODE) {
    structured_log("ERROR", "Invalid YAML structure");
    yaml_document_delete(&document);
    yaml_parser_delete(&parser);
    fclose(fh);
    free(config);
    return NULL;
  }

  yaml_document_delete(&document);
  yaml_parser_delete(&parser);
  fclose(fh);

  return config;
}

void cleanup_hydrant(HydrantContext *ctx) {
  if (!ctx)
    return;

  char *final_status = get_detailed_status(ctx);
  if (final_status) {
    structured_log("INFO", "Final hydrant status: %s", final_status);
    free(final_status);
  }

  stop_workers(ctx);

  pthread_mutex_lock(&ctx->pool_mutex);
  for (int i = 0; i < MAX_POOL_SIZE; i++) {
    if (ctx->pool[i].conn) {
      PQfinish(ctx->pool[i].conn);
      ctx->pool[i].conn = NULL;
    }
  }

  pthread_mutex_unlock(&ctx->pool_mutex);
  pthread_mutex_destroy(&ctx->stats_mutex);
  pthread_mutex_destroy(&ctx->pool_mutex);
  pthread_mutex_destroy(&ctx->batch_mutex);
  pthread_cond_destroy(&ctx->pool_cond);

  if (ctx->batch_buffer) {
    free(ctx->batch_buffer);
  }
  if (ctx->batch_stats) {
    free(ctx->batch_stats);
  }
  if (ctx->config) {
    if (ctx->config->db_conn_string) {
      free(ctx->config->db_conn_string);
    }
    free(ctx->config);
  }

  free(ctx);
}

HydrantContext *init_hydrant(const char *config_path) {
  HydrantContext *ctx = calloc(1, sizeof(HydrantContext));
  if (!ctx) {
    structured_log("ERROR", "Failed to allocate context: %s", strerror(errno));
    return NULL;
  }

  ctx->config = load_config(config_path);
  if (!ctx->config) {
    structured_log("ERROR", "Failed to load configuration");
    free(ctx);
    return NULL;
  }

  if (ctx->config->batch_size < MIN_BATCH_SIZE) {
    structured_log("WARN", "Batch size %zu below minimum, using %d",
                   ctx->config->batch_size, MIN_BATCH_SIZE);
    ctx->config->batch_size = MIN_BATCH_SIZE;
  }
  if (ctx->config->batch_size > MAX_BATCH_SIZE) {
    structured_log("WARN", "Batch size %zu above maximum, using %d",
                   ctx->config->batch_size, MAX_BATCH_SIZE);
    ctx->config->batch_size = MAX_BATCH_SIZE;
  }

  if (pthread_mutex_init(&ctx->stats_mutex, NULL) != 0 ||
      pthread_mutex_init(&ctx->pool_mutex, NULL) != 0 ||
      pthread_mutex_init(&ctx->batch_mutex, NULL) != 0 ||
      pthread_cond_init(&ctx->pool_cond, NULL) != 0) {
    structured_log("ERROR", "Failed to initialize mutex/cond: %s",
                   strerror(errno));
    cleanup_hydrant(ctx);
    return NULL;
  }

  // connection pool
  ctx->healthy_connections = 0;
  for (int i = 0; i < MAX_POOL_SIZE; i++) {
    PoolConnection *pc = &ctx->pool[i];
    pc->conn = PQconnectdb(ctx->config->db_conn_string);

    if (PQstatus(pc->conn) != CONNECTION_OK) {
      structured_log("ERROR", "Failed to connect to DB: %s",
                     PQerrorMessage(pc->conn));
      pc->state = CONN_DEAD;
      snprintf(pc->last_error, MAX_ERROR_LENGTH, "%s",
               PQerrorMessage(pc->conn));
    } else {
      if (ctx->config->require_ssl && !PQsslInUse(pc->conn)) {
        structured_log("ERROR", "SSL required but not in use for connection %d",
                       i);
        pc->state = CONN_DEAD;
      } else {
        PGresult *res =
            PQprepare(pc->conn, "copy_stmt",
                      "COPY original_copy(source_id, content, seq_num, "
                      "checksum) FROM STDIN WITH (FORMAT binary)",
                      0, NULL);
        if (PQresultStatus(res) != PGRES_COMMAND_OK) {
          structured_log("ERROR", "Failed to prepare statement: %s",
                         PQerrorMessage(pc->conn));
          pc->state = CONN_DEAD;
          PQclear(res);
        } else {
          pc->state = CONN_AVAILABLE;
          ctx->healthy_connections++;
          PQclear(res);
        }
      }
    }

    pc->failed_attempts = 0;
    pc->recovery_attempts = 0;
    pc->last_used = 0;
    pc->next_recovery_attempt = 0;
  }

  if (ctx->healthy_connections == 0) {
    structured_log("ERROR", "No healthy connections available");
    cleanup_hydrant(ctx);
    return NULL;
  }

  ctx->batch_buffer = malloc(ctx->config->batch_size);
  if (!ctx->batch_buffer) {
    structured_log("ERROR", "Failed to allocate batch buffer: %s",
                   strerror(errno));
    cleanup_hydrant(ctx);
    return NULL;
  }

  ctx->batch_stats_size = 1000; // Keep last 1000 batch stats
  ctx->batch_stats = calloc(ctx->batch_stats_size, sizeof(BatchStats));
  if (!ctx->batch_stats) {
    structured_log("ERROR", "Failed to allocate batch stats: %s",
                   strerror(errno));
    cleanup_hydrant(ctx);
    return NULL;
  }

  ctx->stats.start_time = time(NULL);
  ctx->stats.last_batch = ctx->stats.start_time;

  if (!start_workers(ctx, 2)) { // Start with 2 workers
    structured_log("ERROR", "Failed to start workers");
    cleanup_hydrant(ctx);
    return NULL;
  }

  structured_log(
      "INFO", "Hydrant initialized successfully with %zu healthy connections",
      ctx->healthy_connections);
  return ctx;
}

void request_shutdown(HydrantContext *ctx) {
  structured_log("INFO", "Shutdown requested");
  atomic_store(&ctx->shutdown_requested, true);
  stop_workers(ctx);

  pthread_mutex_lock(&ctx->batch_mutex);
  if (ctx->current_batch_pos > 0) {
    size_t processed = 0, failed = 0;
    if (!flush_batch(ctx, &processed, &failed)) {
      structured_log("ERROR", "Failed to flush final batch: %zu bytes lost",
                     failed);
    }
  }
  pthread_mutex_unlock(&ctx->batch_mutex);

  cleanup_hydrant(ctx);
}
