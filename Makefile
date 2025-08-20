# Makefile for building and benchmarking filter implementations

# Input/output files
INPUT_IMAGE ?= input.png
OUTPUT_IMAGE ?= output.png
RADIUS ?= 5
WORKERS ?= 64
OPERATION ?= blur

# Build targets
.PHONY: all clean c go rust rust-async odin zig bench bench-operation test

all: c go rust rust-async odin zig

c:
	@echo "Building C implementation..."
	cd c && make

go:
	@echo "Building Go implementation..."
	cd go && go build -ldflags="-s -w" -o filter_go .

rust:
	@echo "Building Rust implementation..."
	cd rust && cargo build --release

rust-async:
	@echo "Building Rust async implementation..."
	cd rust_async && cargo build --release; \

odin:
	@echo "Building Odin implementation..."
	cd odin && odin build . -out:filter_odin -o:aggressive -no-bounds-check

zig:
	@echo "Building Zig implementation..."
	cd zig && zig build -Doptimize=ReleaseFast

# Clean all built binaries
clean:
	@echo "Cleaning built binaries..."
	cd c && make clean
	@rm -f go/filter_go
	@rm -rf zig/zig-out
	@rm -rf zig/.zig-cache
	@cd rust && cargo clean
	@if [ -d "rust_async" ]; then cd rust_async && cargo clean; fi
	@rm -f $(OUTPUT_IMAGE) test_*.png
	@echo "Clean complete"

# Individual benchmarks
bench-c: c
	@echo "Benchmarking C implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./c/filter_c $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./c/filter_c $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./c/filter_c $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 16" \
		"./c/filter_c $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 64" \
		"./c/filter_c $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 128"

bench-go: go
	@echo "Benchmarking Go implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./go/filter_go $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./go/filter_go $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./go/filter_go $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 16" \
		"./go/filter_go $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 64" \
		"./go/filter_go $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 128"

bench-rust: rust
	@echo "Benchmarking Rust threads implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./rust/target/release/rust_filter $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./rust/target/release/rust_filter $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./rust/target/release/rust_filter $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 16" \
		"./rust/target/release/rust_filter $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 64" \
		"./rust/target/release/rust_filter $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 128"

bench-rust-async: rust-async
	@echo "Benchmarking Rust async implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./rust_async/target/release/rust_filter_async $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./rust_async/target/release/rust_filter_async $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./rust_async/target/release/rust_filter_async $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 16" \
		"./rust_async/target/release/rust_filter_async $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 64" \
		"./rust_async/target/release/rust_filter_async $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 128"

bench-odin: odin
	@echo "Benchmarking Odin implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./odin/filter_odin $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./odin/filter_odin $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./odin/filter_odin $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 16" \
		"./odin/filter_odin $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 64" \
		"./odin/filter_odin $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 128"

bench-zig: zig
	@echo "Benchmarking Zig implementation..."
	hyperfine --warmup 3 --runs 10 \
		"./zig/zig-out/bin/filter_zig $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 1" \
		"./zig/zig-out/bin/filter_zig $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 4" \
		"./zig/zig-out/bin/filter_zig $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 16" \
		"./zig/zig-out/bin/filter_zig $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 64" \
		"./zig/zig-out/bin/filter_zig $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) 128"

# Compare all implementations
bench: all
	@echo "Benchmarking $(OPERATION) operation with $(WORKERS) workers..."
	hyperfine --warmup 2 --runs 5 \
		-n "C $(OPERATION)" "./c/filter_c $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)" \
		-n "Go $(OPERATION)" "./go/filter_go $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)" \
		-n "Rust $(OPERATION)" "./rust/target/release/rust_blur $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)" \
		-n "Rust-async $(OPERATION)" "./rust_async/target/release/rust_blur_async $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)" \
		-n "Zig $(OPERATION)" "./zig/zig-out/bin/filter_zig $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)" \
		-n "Odin $(OPERATION)" "./odin/filter_odin $(OPERATION) $(INPUT_IMAGE) $(OUTPUT_IMAGE) $(RADIUS) $(WORKERS)"

# Help target
help:
	@echo "Build targets:"
	@echo "  make all         - Build all implementations"
	@echo "  make c           - Build C implementation"
	@echo "  make go          - Build Go implementation"
	@echo "  make rust        - Build Rust implementation"
	@echo "  make rust-async  - Build Rust async implementation"
	@echo "  make odin        - Build Odin implementation"
	@echo "  make zig         - Build Zig implementation"
	@echo "  make clean       - Remove all built binaries and test images"
	@echo ""
	@echo "Benchmark targets:"
	@echo "  make bench            - Compare all implementations for specified OPERATION"
	@echo ""
	@echo "Environment variables:"
	@echo "  INPUT_IMAGE  - Input image file (default: input.png)"
	@echo "  OUTPUT_IMAGE - Output image file (default: output.png)"
	@echo "  RADIUS       - Filter radius (default: 5)"
	@echo "  WORKERS      - Number of workers/threads (default: 64)"
	@echo "  OPERATION    - Filter operation: 'blur' or 'kuwahara' (default: blur)"
	@echo ""
	@echo "Examples:"
	@echo "  make bench OPERATION=kuwahara WORKERS=8"

.DEFAULT_GOAL := help
