#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <pthread.h>
#include <time.h>

#define STB_IMAGE_IMPLEMENTATION
#include "../stb/stb_image.h"
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "../stb/stb_image_write.h"

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

// Load image using stb_image
Image* load_image(const char* filename) {
    int width, height, channels;
    // Force loading with 4 channels (RGBA)
    unsigned char* data = stbi_load(filename, &width, &height, &channels, 4);
    if (!data) {
        return NULL;
    }

    Image* img = (Image*)malloc(sizeof(Image));
    img->width = width;
    img->height = height;
    img->channels = 4;  // Always 4 channels
    img->data = data;

    return img;
}

// Save image using stb_image_write
int save_image(const char* filename, Image* img) {
    return stbi_write_png(filename, img->width, img->height, img->channels,
                         img->data, img->width * img->channels);
}

// Free image memory
void free_image(Image* img) {
    if (img) {
        if (img->data) {
            stbi_image_free(img->data);
        }
        free(img);
    }
}

// Get current time in milliseconds
long get_time_ms() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int main(int argc, char* argv[]) {
    if (argc != 5) {
        fprintf(stderr, "Usage: %s <input_image> <output_image> <radius> <workers>\n", argv[0]);
        return 1;
    }

    const char* input_path = argv[1];
    const char* output_path = argv[2];
    int radius = atoi(argv[3]);
    int num_workers = atoi(argv[4]);

    // Load image
    long start_time = get_time_ms();
    Image* src = load_image(input_path);
    if (!src) {
        fprintf(stderr, "Failed to load image: %s\n", input_path);
        return 1;
    }
    long load_time = get_time_ms() - start_time;

    printf("Image loaded: %dx%d pixels, %d channels\n", src->width, src->height, src->channels);
    printf("Load time: %ldms\n", load_time);

    // Allocate destination image
    Image* dst = (Image*)malloc(sizeof(Image));
    dst->width = src->width;
    dst->height = src->height;
    dst->channels = src->channels;
    dst->data = (unsigned char*)malloc(src->width * src->height * 4);

    // Apply blur
    start_time = get_time_ms();
    gaussian_blur(src, dst, radius, num_workers);
    long blur_time = get_time_ms() - start_time;

    printf("Blur time: %ldms\n", blur_time);

    // Save image
    start_time = get_time_ms();
    if (!save_image(output_path, dst)) {
        fprintf(stderr, "Failed to save image: %s\n", output_path);
        free_image(src);
        free(dst->data);
        free(dst);
        return 1;
    }
    long save_time = get_time_ms() - start_time;

    printf("Save time: %ldms\n", save_time);
    printf("Total time: %ldms\n", load_time + blur_time + save_time);

    // Clean up
    free_image(src);
    free(dst->data);
    free(dst);

    return 0;
}
