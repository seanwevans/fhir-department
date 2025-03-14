// src/hydrant.c
// Usage: hydrant  [config_file]  [input_file]

#include <stdio.h>
#include <stdlib.h>

#include "hydrant.h"

int main(int argc, char *argv[]) {
  const char *config_path = (argc > 1) ? argv[1] : NULL;
  HydrantContext *ctx = init_hydrant(config_path);
  if (!ctx) {
    fprintf(stderr, "Failed to initialize Hydrant context\n");
    return EXIT_FAILURE;
  }
  structured_log("INFO", "Hydrant system initialized successfully.");

  if (argc > 2) {
    const char *input_file = argv[2];
    FILE *fp = fopen(input_file, "r");
    if (!fp) {
      structured_log("ERROR", "Unable to open input file: %s", input_file);
      request_shutdown(ctx);
      return EXIT_FAILURE;
    }
    structured_log("INFO", "Processing input from file: %s", input_file);
    char buffer[1024];
    size_t n;
    while ((n = fread(buffer, 1, sizeof(buffer), fp)) > 0) {
      if (!add_to_batch(ctx, buffer, n)) {
        size_t processed = 0, failed = 0;
        if (!flush_batch(ctx, &processed, &failed)) {
          structured_log("ERROR", "Batch flush failed.");
        }
        update_batch_stats(ctx, processed, failed);

        if (!add_to_batch(ctx, buffer, n)) {
          structured_log("ERROR", "Failed to add data after flushing batch.");
          break;
        }
      }
    }
    fclose(fp);
  } else {
    structured_log("INFO", "Processing input from STDIN. Press Ctrl-D (Unix) "
                           "or Ctrl-Z (Windows) to end.");
    process_input(ctx);
  }

  char *status = get_detailed_status(ctx);
  if (status) {
    structured_log("INFO", "Detailed status: %s", status);
    free(status);
  }

  request_shutdown(ctx);
  structured_log("INFO", "Hydrant system shutdown complete.");
  return EXIT_SUCCESS;
}
