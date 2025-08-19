# Modern Concurrency Comparison: Image Blur Implementations

This project compares different concurrency models across Go, Rust, and Odin by implementing a CPU-intensive box blur algorithm for images. *My experience level for each language is different and may influence the result*

- I will try to get this up to date with modern implementation for each language I know.
- I will not try to make the fastest program. I want to see if I were to put in reasonable effort for each language of choice to make a meaningful program, how fast should I expect it to run.

Basically we are taking this in

![input](input.png)

And produce this out

![output](output.png)

## Implementations

- **Go**: Goroutines with channels for work distribution
- **Rust (threads)**: OS threads with `Arc<Mutex>` for shared state
- **Rust (async)**: Tokio async tasks with async mutex
- **Odin**: OS threads

## Algorithm

All implementations use the same box blur algorithm:
- Divides the image into horizontal strips
- Distributes strips to workers/threads/tasks
- Each worker processes pixels independently
- Results are collected into the output image

Some optimization has been made:
- **Row buffering**: Process entire rows before writing to minimize lock contention
- **Pre-assigned work**: Avoid work-stealing patterns that cause contention

## Running

You need go, odin, rust compiler installed along with `hyperfine`. Then run `make bench` to run compare all languages. You can run individual benchmark with `make bench-<language>`
```bash
# run all bench
make bench
# run individual bench
make bench-go
make bench-odin
make bench-rust
make bench-rust-async
# custom parameters
INPUT_IMAGE=large.jpg WORKERS=16 make bench
```

## Benchmark Results

Benchmarks performed on `input.png` (500x500) with radius 5.

### Key Observations

Performance with different worker counts:

| Implementation | 1 Worker | 4 Workers | 16 Workers | 64 Workers | 128 Workers | Best Performance |
|---------------|----------|-----------|------------|------------|-------------|------------------|
| **Go** | 357.7 ms | 114.2 ms | 86.1 ms | 109.3 ms | 148.9 ms | 16 workers |
| **Rust threads** | 36.1 ms | 12.0 ms | 8.2 ms | 11.2 ms | 14.6 ms | 16 threads |
| **Rust async** | 41.9 ms | 13.0 ms | 9.5 ms | 12.8 ms | 16.0 ms | 16 tasks |
| **Odin** | 13.4 ms | 20.0 ms | 18.4 ms | 19.2 ms | 22.6 ms | 1 thread (!) |

| Implementation | 1→4 Speedup | 4→16 Speedup | 16→64 Change | 64→128 Change | Optimal Thread Count |
|---------------|-------------|--------------|--------------|---------------|---------------------|
| **Go** | 3.13x | 1.33x | 0.79x (worse) | 0.73x (worse) | 16 |
| **Rust threads** | 3.01x | 1.46x | 0.73x (worse) | 0.77x (worse) | 16 |
| **Rust async** | 3.22x | 1.37x | 0.74x (worse) | 0.80x (worse) | 16 |
| **Odin** | 0.67x (worse) | 1.09x | 0.96x (worse) | 0.85x (worse) | 1 |

| Implementation | Threads/Workers | Mean Time | Relative Speed |
|----------------|----------------|-----------|----------------|
| **Rust threads** | 16 threads | 8.2 ms | 1.00x (fastest) |
| **Rust async** | 16 tasks | 9.5 ms | 1.16x slower |
| **Odin** | 1 thread | 13.4 ms | 1.63x slower |
| **Go** | 16 workers | 86.1 ms | 10.5x slower |

#### Rust threads
Best overall performance at 16 threads (8.2 ms). Excellent scaling from 1→16 threads (4.4x speedup), but degrades at 64 threads and further at 128 threads due to oversaturation and context switching overhead.

#### Rust async (Tokio)
Close second at 16 tasks (9.5 ms). Similar scaling pattern to threads but with slightly more overhead from the async runtime. Performance degrades beyond 16 tasks.

#### Odin
Fastest single-threaded performance (13.4 ms) but gets **slower** with more threads, likely because implementation issue

#### Go
Highest overhead but good scaling (4.15x speedup from 1→16). Performance significantly degrades at 128 workers (148.9 ms), likely because channels and goroutine scheduling overhead

## And The Winner Is

- **Best performance**: Rust threads at 16 threads (8.2 ms)
- **Best single-threaded**: Odin (13.4 ms)
