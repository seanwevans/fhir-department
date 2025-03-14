# fhir-department makefile

CC = gcc
CFLAGS = -std=c11 -Wall -Wextra -Iinclude -pthread
HYDR_LDFLAGS = -lpq -lyaml -lpthread
HOSE_LDFLAGS = -lcurl -lpthread -lncurses
SRC_DIR = src
OBJ_DIR = obj

HYDR_SRCS = $(SRC_DIR)/worker.c $(SRC_DIR)/log.c $(SRC_DIR)/connection.c $(SRC_DIR)/batch.c $(SRC_DIR)/init.c $(SRC_DIR)/hydrant.c
HYDR_OBJS = $(patsubst $(SRC_DIR)/%.c, $(OBJ_DIR)/%.o, $(HYDR_SRCS))

HOSE_SRCS = $(SRC_DIR)/hose.c
HOSE_OBJS = $(patsubst $(SRC_DIR)/%.c, $(OBJ_DIR)/%.o, $(HOSE_SRCS))

TARGETS = hydrant hose

all: $(TARGETS)

hydrant: $(HYDR_OBJS)
	$(CC) $^ -o $@ $(HYDR_LDFLAGS)

hose: $(HOSE_OBJS)
	$(CC) $^ -o $@ $(HOSE_LDFLAGS)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

clean:
	rm -rf $(OBJ_DIR) $(TARGETS)

.PHONY: all clean
