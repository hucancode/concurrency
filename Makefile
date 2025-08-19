# Makefile for building and benchmarking blur implementations

# Input/output files
INPUT_IMAGE ?= input.png
OUTPUT_IMAGE ?= output.png
RADIUS ?= 5
WORKERS ?= 8

# Build targets
.PHONY: all clean go rust rust-async odin

all: go rust rust-async odin

# Go - build with optimizations
go:
	@echo "Building Go implementation..."
	cd go && go build -ldflags="-s -w" -o blur_go blur.go
	@echo "Go binary built: go/blur_go"

# Rust threads - build release mode
rust:
	@echo "Building Rust threads implementation..."
	cd rust && cargo build --release
	@cp rust/target/release/rust_blur rust/blur_rust
	@echo "Rust binary built: rust/blur_rust"

# Rust async - build release mode
rust-async:
	@echo "Building Rust async implementation..."
	cd rust_async && cargo build --release
	@cp rust_async/target/release/rust_blur_async rust_async/blur_rust_async
	@echo "Rust async binary built: rust_async/blur_rust_async"

# Odin - build with optimizations
odin:
	@echo "Building Odin implementation..."
	cd odin && odin build . -out:blur_odin -o:aggressive -no-bounds-check
	@echo "Odin binary built: odin/blur_odin"

# Clean all built binaries
clean:
	@echo "Cleaning built binaries..."
	@rm -f go/blur_go
	@rm -f rust/blur_rust
	@rm -f rust_async/blur_rust_async
	@rm -f odin/blur_odin
	@rm -f $(OUTPUT_IMAGE)
	@cd rust && cargo clean
	@cd rust_async && cargo clean
	@echo "Clean complete"

# Benchmark targets using hyperfine
.PHONY: benchmark bench-go bench-rust bench-rust-async bench-odin bench-all

# Individual benchmarks
bench-go: go
	@echo "Benchmarking Go implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./go/blur_go $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./go/blur_go $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 2" \
		"./go/blur_go $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./go/blur_go $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 8"

bench-rust: rust
	@echo "Benchmarking Rust threads implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./rust/blur_rust $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./rust/blur_rust $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 2" \
		"./rust/blur_rust $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./rust/blur_rust $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 8"

bench-rust-async: rust-async
	@echo "Benchmarking Rust async implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./rust_async/blur_rust_async $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./rust_async/blur_rust_async $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 2" \
		"./rust_async/blur_rust_async $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./rust_async/blur_rust_async $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 8"

bench-odin: odin
	@echo "Benchmarking Odin implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./odin/blur_odin $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./odin/blur_odin $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 2" \
		"./odin/blur_odin $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./odin/blur_odin $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 8"

# Compare all implementations
bench: all
	@echo "Benchmarking all implementations..."
	hyperfine --warmup 3 --runs 10 \
		-n "Go ($(WORKERS) workers)" "./go/blur_go $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)" \
		-n "Rust threads ($(WORKERS) threads)" "./rust/blur_rust $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)" \
		-n "Rust async ($(WORKERS) tasks)" "./rust_async/blur_rust_async $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)" \
		-n "Odin ($(WORKERS) threads)" "./odin/blur_odin $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)"

# Help target
help:
	@echo "Clean:"
	@echo "  make clean       - Remove all built binaries"
	@echo ""
	@echo "Benchmark targets:"
	@echo "  make bench-go         - Benchmark Go with different worker counts"
	@echo "  make bench-rust       - Benchmark Rust threads with different worker counts"
	@echo "  make bench-rust-async - Benchmark Rust async with different worker counts"
	@echo "  make bench-odin       - Benchmark Odin with different worker counts"
	@echo "  make bench            - Compare all implementations"
	@echo ""
	@echo "Environment variables:"
	@echo "  INPUT_IMAGE  - Input image file (default: input.png)"
	@echo "  OUTPUT_IMAGE - Output image file (default: output.png)"
	@echo "  RADIUS       - Blur radius (default: 5)"
	@echo "  WORKERS      - Number of workers/threads (default: 8)"
	@echo ""
	@echo "Examples:"
	@echo "  INPUT_IMAGE=photo.jpg; make bench"

.DEFAULT_GOAL := help
