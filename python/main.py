#!/usr/bin/env python3
import sys
import time
from blur import apply_gaussian_blur
from kuwahara import apply_kuwahara_filter
import numpy as np
from PIL import Image

def main():
    if len(sys.argv) != 6:
        print(f"Usage: {sys.argv[0]} <filter_type> <input_image> <output_image> <radius> <workers>")
        print("Filter types: blur, kuwahara")
        sys.exit(1)
    
    filter_type = sys.argv[1].lower()
    input_path = sys.argv[2]
    output_path = sys.argv[3]
    radius = int(sys.argv[4])
    num_workers = int(sys.argv[5])
    
    if filter_type not in ['blur', 'kuwahara']:
        print(f"Unknown filter type: {filter_type}")
        print("Available filters: blur, kuwahara")
        sys.exit(1)
    
    # Load image
    start_time = time.time()
    img = Image.open(input_path).convert('RGBA')
    img_array = np.array(img, dtype=np.float32)
    load_time = time.time() - start_time
    print(f"Image loading took {load_time * 1000:.2f}ms")
    
    # Apply filter
    start_time = time.time()
    if filter_type == 'blur':
        filtered_array = apply_gaussian_blur(img_array, radius, num_workers)
    else:  # kuwahara
        filtered_array = apply_kuwahara_filter(img_array, radius, num_workers)
    filter_time = time.time() - start_time
    print(f"{filter_type.capitalize()} processing took {filter_time * 1000:.2f}ms")
    
    # Save image
    start_time = time.time()
    filtered_array = np.clip(filtered_array, 0, 255).astype(np.uint8)
    filtered_img = Image.fromarray(filtered_array)
    filtered_img.save(output_path)
    save_time = time.time() - start_time
    print(f"Image saving took {save_time * 1000:.2f}ms")
    
    total_time = load_time + filter_time + save_time
    print(f"Total time: {total_time * 1000:.2f}ms")

if __name__ == "__main__":
    main()