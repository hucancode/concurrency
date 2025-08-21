#!/usr/bin/env python3
import sys
import time
import math
import numpy as np
from PIL import Image
from concurrent.futures import ThreadPoolExecutor
import threading

def generate_gaussian_kernel(radius):
    size = 2 * radius + 1
    kernel = np.zeros(size)
    sigma = radius / 3.0
    
    for i in range(size):
        x = i - radius
        kernel[i] = math.exp(-(x * x) / (2.0 * sigma * sigma))
    
    kernel /= kernel.sum()
    return kernel

def blur_horizontal_chunk(img_array, kernel, radius, start_y, end_y):
    height, width, channels = img_array.shape
    result = np.zeros((end_y - start_y, width, channels), dtype=np.float32)
    
    for y in range(start_y, end_y):
        for x in range(width):
            for c in range(channels):
                pixel_sum = 0.0
                for k in range(-radius, radius + 1):
                    sx = x + k
                    sx = max(0, min(sx, width - 1))
                    weight = kernel[k + radius]
                    pixel_sum += img_array[y, sx, c] * weight
                result[y - start_y, x, c] = pixel_sum
    
    return (start_y, end_y, result)

def apply_gaussian_blur(img_array, radius, num_workers):
    height, width, channels = img_array.shape
    kernel = generate_gaussian_kernel(radius)
    
    # Phase 1: Horizontal blur
    horizontal = np.zeros_like(img_array, dtype=np.float32)
    
    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        futures = []
        rows_per_worker = height // num_workers
        
        for i in range(num_workers):
            start_y = i * rows_per_worker
            end_y = start_y + rows_per_worker if i < num_workers - 1 else height
            future = executor.submit(blur_horizontal_chunk, img_array, kernel, radius, start_y, end_y)
            futures.append(future)
        
        for future in futures:
            start_y, end_y, chunk_result = future.result()
            horizontal[start_y:end_y] = chunk_result
    
    # Transpose for vertical pass
    transposed = np.transpose(horizontal, (1, 0, 2))
    
    # Phase 2: Vertical blur (horizontal on transposed)
    height_t, width_t = transposed.shape[:2]
    blurred = np.zeros_like(transposed, dtype=np.float32)
    
    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        futures = []
        rows_per_worker = height_t // num_workers
        
        for i in range(num_workers):
            start_y = i * rows_per_worker
            end_y = start_y + rows_per_worker if i < num_workers - 1 else height_t
            future = executor.submit(blur_horizontal_chunk, transposed, kernel, radius, start_y, end_y)
            futures.append(future)
        
        for future in futures:
            start_y, end_y, chunk_result = future.result()
            blurred[start_y:end_y] = chunk_result
    
    # Transpose back
    final = np.transpose(blurred, (1, 0, 2))
    return final

def main():
    if len(sys.argv) != 5:
        print(f"Usage: {sys.argv[0]} <input_image> <output_image> <radius> <workers>")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    radius = int(sys.argv[3])
    num_workers = int(sys.argv[4])
    
    # Load image
    start_time = time.time()
    img = Image.open(input_path).convert('RGBA')
    img_array = np.array(img, dtype=np.float32)
    load_time = time.time() - start_time
    print(f"Image loading took {load_time * 1000:.2f}ms")
    
    # Apply blur
    start_time = time.time()
    blurred_array = apply_gaussian_blur(img_array, radius, num_workers)
    blur_time = time.time() - start_time
    print(f"Blur processing took {blur_time * 1000:.2f}ms")
    
    # Save image
    start_time = time.time()
    blurred_array = np.clip(blurred_array, 0, 255).astype(np.uint8)
    blurred_img = Image.fromarray(blurred_array)
    blurred_img.save(output_path)
    save_time = time.time() - start_time
    print(f"Image saving took {save_time * 1000:.2f}ms")
    
    total_time = load_time + blur_time + save_time
    print(f"Total time: {total_time * 1000:.2f}ms")

if __name__ == "__main__":
    main()