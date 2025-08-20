#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <pthread.h>
#include <time.h>
#include <float.h>

typedef struct {
    unsigned char* data;
    int width;
    int height;
    int channels;
} Image;

// External function from main.c
extern long get_time_ms();

typedef struct {
    float* sum;
    float* sum_sq;
    int width;
    int height;
} IntegralImage;

typedef struct {
    Image* src;
    Image* dst;
    IntegralImage* integral;
    int radius;
    int start_row;
    int end_row;
} WorkerContext;

IntegralImage* create_integral_image(int width, int height) {
    IntegralImage* img = (IntegralImage*)malloc(sizeof(IntegralImage));
    img->width = width;
    img->height = height;
    img->sum = (float*)calloc((width + 1) * (height + 1) * 3, sizeof(float));
    img->sum_sq = (float*)calloc((width + 1) * (height + 1) * 3, sizeof(float));
    return img;
}

void free_integral_image(IntegralImage* img) {
    if (img) {
        free(img->sum);
        free(img->sum_sq);
        free(img);
    }
}

void build_integral_images(Image* src, IntegralImage* integral) {
    int w = src->width;
    int h = src->height;
    int iw = integral->width + 1;
    
    for (int y = 1; y <= h; y++) {
        for (int x = 1; x <= w; x++) {
            for (int ch = 0; ch < 3; ch++) {
                int src_idx = ((y - 1) * w + (x - 1)) * 4 + ch;
                float val = src->data[src_idx];
                
                int idx = (y * iw + x) * 3 + ch;
                int idx_up = ((y - 1) * iw + x) * 3 + ch;
                int idx_left = (y * iw + (x - 1)) * 3 + ch;
                int idx_diag = ((y - 1) * iw + (x - 1)) * 3 + ch;
                
                integral->sum[idx] = val + 
                    integral->sum[idx_up] + 
                    integral->sum[idx_left] - 
                    integral->sum[idx_diag];
                
                integral->sum_sq[idx] = val * val + 
                    integral->sum_sq[idx_up] + 
                    integral->sum_sq[idx_left] - 
                    integral->sum_sq[idx_diag];
            }
        }
    }
}

void get_region_stats(IntegralImage* integral, int x1, int y1, int x2, int y2, 
                     float* mean, float* variance, int channel) {
    int iw = integral->width + 1;
    
    x1 = (x1 < 0) ? 0 : x1;
    y1 = (y1 < 0) ? 0 : y1;
    x2 = (x2 >= integral->width) ? integral->width - 1 : x2;
    y2 = (y2 >= integral->height) ? integral->height - 1 : y2;
    
    x1++; y1++; x2++; y2++;
    
    int idx_br = (y2 * iw + x2) * 3 + channel;
    int idx_bl = (y2 * iw + x1 - 1) * 3 + channel;
    int idx_tr = ((y1 - 1) * iw + x2) * 3 + channel;
    int idx_tl = ((y1 - 1) * iw + x1 - 1) * 3 + channel;
    
    float sum = integral->sum[idx_br] - integral->sum[idx_bl] - 
                integral->sum[idx_tr] + integral->sum[idx_tl];
    float sum_sq = integral->sum_sq[idx_br] - integral->sum_sq[idx_bl] - 
                   integral->sum_sq[idx_tr] + integral->sum_sq[idx_tl];
    
    float area = (x2 - x1 + 1) * (y2 - y1 + 1);
    if (area > 0) {
        *mean = sum / area;
        *variance = (sum_sq / area) - (*mean * *mean);
        if (*variance < 0) *variance = 0;
    } else {
        *mean = 0;
        *variance = 0;
    }
}

void kuwahara_filter_pixel(Image* src, Image* dst, IntegralImage* integral, 
                          int x, int y, int radius) {
    float min_variance[3] = {FLT_MAX, FLT_MAX, FLT_MAX};
    float best_mean[3] = {0, 0, 0};
    
    int quadrants[4][4] = {
        {x - radius, y - radius, x, y},
        {x, y - radius, x + radius, y},
        {x - radius, y, x, y + radius},
        {x, y, x + radius, y + radius}
    };
    
    for (int q = 0; q < 4; q++) {
        float mean[3], variance[3];
        float total_variance = 0;
        
        for (int ch = 0; ch < 3; ch++) {
            get_region_stats(integral, 
                           quadrants[q][0], quadrants[q][1],
                           quadrants[q][2], quadrants[q][3],
                           &mean[ch], &variance[ch], ch);
            total_variance += variance[ch];
        }
        
        if (total_variance < min_variance[0] + min_variance[1] + min_variance[2]) {
            for (int ch = 0; ch < 3; ch++) {
                min_variance[ch] = variance[ch];
                best_mean[ch] = mean[ch];
            }
        }
    }
    
    int dst_idx = (y * dst->width + x) * 4;
    for (int ch = 0; ch < 3; ch++) {
        dst->data[dst_idx + ch] = (unsigned char)fminf(255.0f, fmaxf(0.0f, best_mean[ch]));
    }
    dst->data[dst_idx + 3] = src->data[(y * src->width + x) * 4 + 3];
}

void* kuwahara_worker(void* arg) {
    WorkerContext* ctx = (WorkerContext*)arg;
    
    for (int y = ctx->start_row; y < ctx->end_row; y++) {
        for (int x = 0; x < ctx->src->width; x++) {
            kuwahara_filter_pixel(ctx->src, ctx->dst, ctx->integral, x, y, ctx->radius);
        }
    }
    
    return NULL;
}

void apply_kuwahara_filter(Image* src, Image* dst, int radius, int num_workers) {
    IntegralImage* integral = create_integral_image(src->width, src->height);
    
    long start_time = get_time_ms();
    build_integral_images(src, integral);
    long sat_time = get_time_ms() - start_time;
    printf("SAT build time: %ldms\n", sat_time);
    
    pthread_t* threads = (pthread_t*)malloc(num_workers * sizeof(pthread_t));
    WorkerContext* contexts = (WorkerContext*)malloc(num_workers * sizeof(WorkerContext));
    
    int rows_per_worker = src->height / num_workers;
    for (int i = 0; i < num_workers; i++) {
        contexts[i].src = src;
        contexts[i].dst = dst;
        contexts[i].integral = integral;
        contexts[i].radius = radius;
        contexts[i].start_row = i * rows_per_worker;
        contexts[i].end_row = (i == num_workers - 1) ? src->height : (i + 1) * rows_per_worker;
        
        pthread_create(&threads[i], NULL, kuwahara_worker, &contexts[i]);
    }
    
    for (int i = 0; i < num_workers; i++) {
        pthread_join(threads[i], NULL);
    }
    
    free(threads);
    free(contexts);
    free_integral_image(integral);
}

