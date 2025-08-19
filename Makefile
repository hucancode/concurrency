# Makefile for building and benchmarking blur implementations

# Input/output files
INPUT_IMAGE ?= input.png
OUTPUT_IMAGE ?= output.png
RADIUS ?= 5
WORKERS ?= 64

# Build targets
.PHONY: all clean go rust rust-async odin bench-go bench-rust bench-rust-async bench-odin bench

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
	@echo "Rust binary built: rust/target/release/rust_blur"

# Rust async - build release mode
rust-async:
	@echo "Building Rust async implementation..."
	cd rust_async && cargo build --release
	@echo "Rust async binary built: rust_async/target/release/rust_blur_async"

# Odin - build with optimizations
odin:
	@echo "Building Odin implementation..."
	cd odin && odin build . -out:blur_odin -o:aggressive -no-bounds-check
	@echo "Odin binary built: odin/blur_odin"

# Clean all built binaries
clean:
	@echo "Cleaning built binaries..."
	@rm -f go/blur_go
	@rm -f odin/blur_odin
	@rm -f $(OUTPUT_IMAGE)
	@cd rust && cargo clean
	@cd rust_async && cargo clean
	@echo "Clean complete"

# Individual benchmarks
bench-go: go
	@echo "Benchmarking Go implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./go/blur_go $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./go/blur_go $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./go/blur_go $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 16" \
		"./go/blur_go $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 64" \
		"./go/blur_go $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 128"

bench-rust: rust
	@echo "Benchmarking Rust threads implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./rust/target/release/rust_blur $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./rust/target/release/rust_blur $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./rust/target/release/rust_blur $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 16" \
		"./rust/target/release/rust_blur $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 64" \
		"./rust/target/release/rust_blur $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 128"

bench-rust-async: rust-async
	@echo "Benchmarking Rust async implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./rust_async/target/release/rust_blur_async $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./rust_async/target/release/rust_blur_async $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./rust_async/target/release/rust_blur_async $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 16" \
		"./rust_async/target/release/rust_blur_async $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 64" \
		"./rust_async/target/release/rust_blur_async $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 128"

bench-odin: odin
	@echo "Benchmarking Odin implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./odin/blur_odin $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./odin/blur_odin $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./odin/blur_odin $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 16" \
		"./odin/blur_odin $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 64" \
		"./odin/blur_odin $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 128"

# Compare all implementations
bench: all
	@echo "Benchmarking all implementations..."
	hyperfine --warmup 3 --runs 10 \
		-n "Go ($(WORKERS) workers)" "./go/blur_go $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)" \
		-n "Rust threads ($(WORKERS) threads)" "./rust/target/release/rust_blur $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)" \
		-n "Rust async ($(WORKERS) tasks)" "./rust_async/target/release/rust_blur_async $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)" \
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
	@echo "  WORKERS      - Number of workers/threads (default: 64)"
	@echo ""
	@echo "Examples:"
	@echo "  INPUT_IMAGE=photo.jpg; make bench"

.DEFAULT_GOAL := help
