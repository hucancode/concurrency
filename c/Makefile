CC = gcc
CFLAGS = -O3 -march=native -pthread -lm -Wall -Wextra
TARGET = filter_c
SRCS = main.c blur.c kuwahara.c monte_carlo.c
OBJS = $(SRCS:.c=.o)

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(OBJS) -o $(TARGET) $(CFLAGS)

%.o: %.c
	$(CC) -c $< -o $@ $(CFLAGS)

clean:
	rm -f $(TARGET) $(OBJS)

.PHONY: all clean