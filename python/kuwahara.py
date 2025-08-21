#!/usr/bin/env python3
import numpy as np
from multiprocessing import Pool
import time

class IntegralImage:
    def __init__(self, img_array):
        h, w, c = img_array.shape
        # Pad with zeros for easier boundary handling
        self.sum = np.zeros((h + 1, w + 1, c), dtype=np.float64)
        self.sum_sq = np.zeros((h + 1, w + 1, c), dtype=np.float64)
        
        # Build integral images
        for y in range(1, h + 1):
            for x in range(1, w + 1):
                pixel = img_array[y - 1, x - 1]
                self.sum[y, x] = pixel + self.sum[y-1, x] + self.sum[y, x-1] - self.sum[y-1, x-1]
                self.sum_sq[y, x] = pixel * pixel + self.sum_sq[y-1, x] + self.sum_sq[y, x-1] - self.sum_sq[y-1, x-1]
        
        self.height = h
        self.width = w
    
    def get_region_stats(self, x1, y1, x2, y2):
        # Clamp coordinates
        x1 = max(0, x1)
        y1 = max(0, y1)
        x2 = min(self.width - 1, x2)
        y2 = min(self.height - 1, y2)
        
        # Adjust for 1-indexed integral image
        x1 += 1
        y1 += 1
        x2 += 1
        y2 += 1
        
        area = (x2 - x1 + 1) * (y2 - y1 + 1)
        
        if area > 0:
            # Calculate sum using integral image
            sum_val = (self.sum[y2, x2] - self.sum[y2, x1-1] - 
                      self.sum[y1-1, x2] + self.sum[y1-1, x1-1])
            
            # Calculate sum of squares
            sum_sq_val = (self.sum_sq[y2, x2] - self.sum_sq[y2, x1-1] - 
                         self.sum_sq[y1-1, x2] + self.sum_sq[y1-1, x1-1])
            
            mean = sum_val / area
            variance = np.maximum((sum_sq_val / area) - (mean * mean), 0)
            
            return mean, variance
        else:
            return np.zeros(4), np.zeros(4)

def kuwahara_filter_chunk(args):
    img_array, integral, radius, start_y, end_y = args
    height, width, channels = img_array.shape
    result = np.zeros((end_y - start_y, width, channels), dtype=np.float32)
    
    for y in range(start_y, end_y):
        for x in range(width):
            min_variance = float('inf')
            best_mean = None
            
            # Define quadrants
            quadrants = [
                (x - radius, y - radius, x, y),          # Top-left
                (x, y - radius, x + radius, y),          # Top-right
                (x - radius, y, x, y + radius),          # Bottom-left
                (x, y, x + radius, y + radius)           # Bottom-right
            ]
            
            for quad in quadrants:
                mean, variance = integral.get_region_stats(*quad)
                total_variance = variance[:3].sum()  # Sum RGB variances
                
                if total_variance < min_variance:
                    min_variance = total_variance
                    best_mean = mean
            
            # Set pixel to mean of region with minimum variance
            result[y - start_y, x, :3] = best_mean[:3]
            # Preserve alpha channel
            result[y - start_y, x, 3] = img_array[y, x, 3]
    
    return (start_y, end_y, result)

def apply_kuwahara_filter(img_array, radius, num_workers):
    height, width, channels = img_array.shape
    
    # Build integral images (SAT)
    start_time = time.time()
    integral = IntegralImage(img_array)
    sat_time = time.time() - start_time
    print(f"SAT build time: {sat_time * 1000:.0f}ms")
    
    # Apply Kuwahara filter
    output = np.zeros_like(img_array, dtype=np.float32)
    
    with Pool(processes=num_workers) as pool:
        tasks = []
        rows_per_worker = height // num_workers
        
        for i in range(num_workers):
            start_y = i * rows_per_worker
            end_y = start_y + rows_per_worker if i < num_workers - 1 else height
            tasks.append((img_array, integral, radius, start_y, end_y))
        
        results = pool.map(kuwahara_filter_chunk, tasks)
        
        for start_y, end_y, chunk_result in results:
            output[start_y:end_y] = chunk_result
    
    return output