CC = gcc
CFLAGS = -O3 -march=native -pthread -lm -Wall -Wextra
TARGET = blur_c
SRC = blur.c

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(SRC) -o $(TARGET) $(CFLAGS)

clean:
	rm -f $(TARGET)

.PHONY: all clean