#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <pthread.h>

typedef struct {
    unsigned char* data;
    int width;
    int height;
    int channels;
} Image;

typedef struct {
    Image* src;
    Image* dst;
    float* kernel;
    int radius;
    int start_row;
    int end_row;
} WorkerContext;

// Generate Gaussian kernel
float* generate_gaussian_kernel(int radius) {
    int size = 2 * radius + 1;
    float* kernel = (float*)malloc(size * sizeof(float));
    float sigma = radius / 3.0f;
    float sum = 0.0f;

    for (int i = 0; i < size; i++) {
        float x = i - radius;
        kernel[i] = expf(-(x * x) / (2.0f * sigma * sigma));
        sum += kernel[i];
    }

    // Normalize
    for (int i = 0; i < size; i++) {
        kernel[i] /= sum;
    }

    return kernel;
}

// Horizontal blur pass
void blur_horizontal(Image* src, Image* dst, float* kernel, int radius, int start_row, int end_row) {
    int kernel_size = 2 * radius + 1;

    for (int y = start_row; y < end_row; y++) {
        // Process left edge (x < radius)
        for (int x = 0; x < radius && x < src->width; x++) {
            // Always 4 channels now (RGBA)
            for (int ch = 0; ch < 4; ch++) {
                float sum = 0.0f;

                for (int k = 0; k < kernel_size; k++) {
                    int src_x = x + k - radius;
                    if (src_x < 0) src_x = 0;

                    int idx = (y * src->width + src_x) * 4 + ch;
                    sum += src->data[idx] * kernel[k];
                }

                int dst_idx = (y * dst->width + x) * 4 + ch;
                dst->data[dst_idx] = (unsigned char)roundf(sum);
            }
        }

        // Process middle part (no boundary checks needed)
        for (int x = radius; x < src->width - radius; x++) {
            // Always 4 channels now (RGBA)
            for (int ch = 0; ch < 4; ch++) {
                float sum = 0.0f;

                // No bounds checking needed here
                for (int k = 0; k < kernel_size; k++) {
                    int src_x = x + k - radius;
                    int idx = (y * src->width + src_x) * 4 + ch;
                    sum += src->data[idx] * kernel[k];
                }

                int dst_idx = (y * dst->width + x) * 4 + ch;
                dst->data[dst_idx] = (unsigned char)roundf(sum);
            }
        }

        // Process right edge (x >= width - radius)
        for (int x = src->width - radius; x < src->width; x++) {
            if (x < radius) continue;  // Skip if already processed in left edge

            for (int ch = 0; ch < 4; ch++) {
                float sum = 0.0f;

                for (int k = 0; k < kernel_size; k++) {
                    int src_x = x + k - radius;
                    if (src_x >= src->width) src_x = src->width - 1;

                    int idx = (y * src->width + src_x) * 4 + ch;
                    sum += src->data[idx] * kernel[k];
                }

                int dst_idx = (y * dst->width + x) * dst->channels + ch;
                dst->data[dst_idx] = (unsigned char)roundf(sum);
            }
        }
    }
}

// Transpose image for cache-friendly vertical blur
void transpose_image(Image* src, Image* dst) {
    for (int y = 0; y < src->height; y++) {
        for (int x = 0; x < src->width; x++) {
            for (int ch = 0; ch < 4; ch++) {
                int src_idx = (y * src->width + x) * 4 + ch;
                int dst_idx = (x * src->height + y) * 4 + ch;
                dst->data[dst_idx] = src->data[src_idx];
            }
        }
    }
}

// Worker thread function
void* worker_thread(void* arg) {
    WorkerContext* ctx = (WorkerContext*)arg;
    blur_horizontal(ctx->src, ctx->dst, ctx->kernel, ctx->radius, ctx->start_row, ctx->end_row);
    return NULL;
}

// Apply Gaussian blur with multiple threads
void gaussian_blur(Image* src, Image* dst, int radius, int num_workers) {
    float* kernel = generate_gaussian_kernel(radius);

    // Allocate temporary buffers
    Image temp1 = {
        .data = (unsigned char*)malloc(src->width * src->height * 4),
        .width = src->width,
        .height = src->height,
        .channels = 4
    };

    Image temp2 = {
        .data = (unsigned char*)malloc(src->width * src->height * 4),
        .width = src->height,  // Swapped for transpose
        .height = src->width,
        .channels = 4
    };

    // Create worker contexts and threads
    pthread_t* threads = (pthread_t*)malloc(num_workers * sizeof(pthread_t));
    WorkerContext* contexts = (WorkerContext*)malloc(num_workers * sizeof(WorkerContext));

    // Phase 1: Horizontal blur
    int rows_per_worker = src->height / num_workers;
    for (int i = 0; i < num_workers; i++) {
        contexts[i].src = src;
        contexts[i].dst = &temp1;
        contexts[i].kernel = kernel;
        contexts[i].radius = radius;
        contexts[i].start_row = i * rows_per_worker;
        contexts[i].end_row = (i == num_workers - 1) ? src->height : (i + 1) * rows_per_worker;

        pthread_create(&threads[i], NULL, worker_thread, &contexts[i]);
    }

    // Wait for all threads to complete
    for (int i = 0; i < num_workers; i++) {
        pthread_join(threads[i], NULL);
    }

    // Transpose for vertical pass
    transpose_image(&temp1, &temp2);

    // Create temp3 for the second blur pass result
    Image temp3 = {
        .data = (unsigned char*)malloc(src->width * src->height * 4),
        .width = src->height,  // Still transposed
        .height = src->width,
        .channels = 4
    };

    // Phase 2: Vertical blur (horizontal on transposed)
    rows_per_worker = src->width / num_workers;
    for (int i = 0; i < num_workers; i++) {
        contexts[i].src = &temp2;
        contexts[i].dst = &temp3;
        contexts[i].kernel = kernel;
        contexts[i].radius = radius;
        contexts[i].start_row = i * rows_per_worker;
        contexts[i].end_row = (i == num_workers - 1) ? src->width : (i + 1) * rows_per_worker;

        pthread_create(&threads[i], NULL, worker_thread, &contexts[i]);
    }

    // Wait for all threads to complete
    for (int i = 0; i < num_workers; i++) {
        pthread_join(threads[i], NULL);
    }

    // Transpose back to original orientation
    transpose_image(&temp3, dst);

    // Clean up
    free(temp1.data);
    free(temp2.data);
    free(temp3.data);
    free(kernel);
    free(threads);
    free(contexts);
}

