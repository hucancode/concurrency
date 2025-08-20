#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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

// External filter functions
void gaussian_blur(Image* src, Image* dst, int radius, int num_workers);
void apply_kuwahara_filter(Image* src, Image* dst, int radius, int num_workers);

Image* load_image(const char* filename) {
    int width, height, channels;
    unsigned char* data = stbi_load(filename, &width, &height, &channels, 4);
    if (!data) {
        return NULL;
    }
    
    Image* img = (Image*)malloc(sizeof(Image));
    img->width = width;
    img->height = height;
    img->channels = 4;
    img->data = data;
    
    return img;
}

int save_image(const char* filename, Image* img) {
    return stbi_write_png(filename, img->width, img->height, img->channels,
                         img->data, img->width * img->channels);
}

void free_image(Image* img) {
    if (img) {
        if (img->data) {
            stbi_image_free(img->data);
        }
        free(img);
    }
}

long get_time_ms() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

void print_usage(const char* program) {
    fprintf(stderr, "Usage: %s <operation> <input_image> <output_image> <radius> <workers>\n", program);
    fprintf(stderr, "  operation: 'blur' or 'kuwahara'\n");
}

int main(int argc, char* argv[]) {
    if (argc != 6) {
        print_usage(argv[0]);
        return 1;
    }
    
    const char* operation = argv[1];
    const char* input_path = argv[2];
    const char* output_path = argv[3];
    int radius = atoi(argv[4]);
    int num_workers = atoi(argv[5]);
    
    long start_time = get_time_ms();
    Image* src = load_image(input_path);
    if (!src) {
        fprintf(stderr, "Failed to load image: %s\n", input_path);
        return 1;
    }
    long load_time = get_time_ms() - start_time;
    
    printf("Image loaded: %dx%d pixels, %d channels\n", src->width, src->height, src->channels);
    printf("Load time: %ldms\n", load_time);
    
    Image* dst = (Image*)malloc(sizeof(Image));
    dst->width = src->width;
    dst->height = src->height;
    dst->channels = src->channels;
    dst->data = (unsigned char*)malloc(src->width * src->height * 4);
    
    start_time = get_time_ms();
    if (strcmp(operation, "blur") == 0) {
        printf("Applying Gaussian blur with radius %d using %d workers\n", radius, num_workers);
        gaussian_blur(src, dst, radius, num_workers);
    } else if (strcmp(operation, "kuwahara") == 0) {
        printf("Applying Kuwahara filter with radius %d using %d workers\n", radius, num_workers);
        apply_kuwahara_filter(src, dst, radius, num_workers);
    } else {
        fprintf(stderr, "Unknown operation: %s. Use 'blur' or 'kuwahara'\n", operation);
        free_image(src);
        free(dst->data);
        free(dst);
        return 1;
    }
    long filter_time = get_time_ms() - start_time;
    
    printf("Filter time: %ldms\n", filter_time);
    
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
    printf("Total time: %ldms\n", load_time + filter_time + save_time);
    
    free_image(src);
    free(dst->data);
    free(dst);
    
    return 0;
}