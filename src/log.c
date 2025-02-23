// src/log.c

#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#include "hydrant.h"

static pthread_mutex_t log_mutex = PTHREAD_MUTEX_INITIALIZER;

static void json_escape(char *dest, const char *src, size_t dest_size) {
  size_t di = 0;

  for (size_t si = 0; src[si] && di < dest_size - 1; si++) {
    switch (src[si]) {
    case '"':
      if (di + 2 >= dest_size)
        goto end;
      dest[di++] = '\\';
      dest[di++] = '"';
      break;
    case '\\':
      if (di + 2 >= dest_size)
        goto end;
      dest[di++] = '\\';
      dest[di++] = '\\';
      break;
    case '\n':
      if (di + 2 >= dest_size)
        goto end;
      dest[di++] = '\\';
      dest[di++] = 'n';
      break;
    case '\r':
      if (di + 2 >= dest_size)
        goto end;
      dest[di++] = '\\';
      dest[di++] = 'r';
      break;
    case '\t':
      if (di + 2 >= dest_size)
        goto end;
      dest[di++] = '\\';
      dest[di++] = 't';
      break;
    default:
      if ((unsigned char)src[si] < 32) {
        if (di + 6 >= dest_size)
          goto end;
        snprintf(dest + di, 7, "\\u%04x", src[si]);
        di += 6;
      } else {
        dest[di++] = src[si];
      }
    }
  }
end:
  dest[di] = '\0';
}

void structured_log(const char *level, const char *format, ...) {
  char timestamp[32];
  char message[MAX_ERROR_LENGTH];
  char escaped_message[MAX_ERROR_LENGTH * 2];

  va_list args;
  va_start(args, format);
  vsnprintf(message, sizeof(message), format, args);
  va_end(args);

  time_t now = time(NULL);
  struct tm tm_buf;
  strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%S%z",
           localtime_r(&now, &tm_buf));

  json_escape(escaped_message, message, sizeof(escaped_message));

  pthread_mutex_lock(&log_mutex);
  fprintf(stderr,
          "{\"timestamp\":\"%s\","
          "\"level\":\"%s\","
          "\"message\":\"%s\","
          "\"thread\":\"%lx\"}\n",
          timestamp, level, escaped_message, (unsigned long)pthread_self());
  fflush(stderr);
  pthread_mutex_unlock(&log_mutex);
}
