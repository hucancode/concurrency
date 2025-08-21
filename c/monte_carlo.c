#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <time.h>

typedef struct {
    int samples;
    unsigned int seed;
    int inside;
} ThreadData;

// Linear Congruential Generator - same formula across all languages
double lcg_random(unsigned int* seed) {
    *seed = *seed * 1664525u + 1013904223u;
    return (double)(*seed & 0x7FFFFFFFu) / (double)0x7FFFFFFFu;
}

void* monte_carlo_worker(void* arg) {
    ThreadData* data = (ThreadData*)arg;
    data->inside = 0;
    
    for (int i = 0; i < data->samples; i++) {
        double x = lcg_random(&data->seed);
        double y = lcg_random(&data->seed);
        if (x * x + y * y <= 1.0) {
            data->inside++;
        }
    }
    
    return NULL;
}

void monte_carlo_operation(int total_samples, int num_workers) {
    if (num_workers <= 0) num_workers = 1;
    
    pthread_t* threads = malloc(num_workers * sizeof(pthread_t));
    ThreadData* thread_data = malloc(num_workers * sizeof(ThreadData));
    
    int samples_per_worker = total_samples / num_workers;
    int remainder = total_samples % num_workers;
    
    for (int i = 0; i < num_workers; i++) {
        thread_data[i].samples = samples_per_worker;
        if (i == num_workers - 1) {
            thread_data[i].samples += remainder;
        }
        thread_data[i].seed = 12345 + i * 67890;  // Consistent seed pattern
        
        pthread_create(&threads[i], NULL, monte_carlo_worker, &thread_data[i]);
    }
    
    int total_inside = 0;
    for (int i = 0; i < num_workers; i++) {
        pthread_join(threads[i], NULL);
        total_inside += thread_data[i].inside;
    }
    
    double pi_estimate = 4.0 * total_inside / total_samples;
    
    printf("Monte Carlo Pi Estimation\n");
    printf("Total samples: %d\n", total_samples);
    printf("Points inside circle: %d\n", total_inside);
    printf("Pi estimate: %.6f\n", pi_estimate);
    printf("Error: %.6f\n", 3.141592653589793 - pi_estimate);
    
    free(threads);
    free(thread_data);
}