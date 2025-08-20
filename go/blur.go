package main

import (
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"log"
	"math"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

// ImageData represents image as a flat array for better performance
type ImageData struct {
	data     []uint8
	width    int
	height   int
	channels int
}

// create a 1D Gaussian kernel
func generateGaussianKernel(radius int) []float64 {
	size := 2*radius + 1
	kernel := make([]float64, size)
	sigma := float64(radius) / 3.0 // Standard deviation
	sum := 0.0

	// Calculate Gaussian values
	for i := range size {
		x := float64(i - radius)
		kernel[i] = math.Exp(-(x*x) / (2.0 * sigma * sigma))
		sum += kernel[i]
	}

	// Normalize kernel
	for i := range size {
		kernel[i] /= sum
	}

	return kernel
}

// transposeImage transposes image data for better cache locality
func transposeImage(src *ImageData) *ImageData {
	dst := &ImageData{
		data:     make([]uint8, len(src.data)),
		width:    src.height, // Swapped
		height:   src.width,  // Swapped
		channels: src.channels,
	}

	for y := range src.height {
		for x := range src.width {
			srcIdx := (y*src.width + x) * src.channels
			dstIdx := (x*src.height + y) * src.channels

			copy(dst.data[dstIdx:dstIdx+src.channels], src.data[srcIdx:srcIdx+src.channels])
		}
	}

	return dst
}

// apply a single pass horizontal Gaussian blur
func horizontalGaussianBlur(src *ImageData, dst *ImageData, kernel []float64, radius int, startY, endY int) {
	for y := startY; y < endY; y++ {
		// Process left edge (x < radius)
		for x := 0; x < radius && x < src.width; x++ {
			var rSum, gSum, bSum, aSum float64

			for k := -radius; k <= radius; k++ {
				sx := max(x + k, 0)

				idx := (y*src.width + sx) * src.channels
				weight := kernel[k+radius]

				rSum += float64(src.data[idx]) * weight
				gSum += float64(src.data[idx+1]) * weight
				bSum += float64(src.data[idx+2]) * weight
				aSum += float64(src.data[idx+3]) * weight
			}

			dstIdx := (y*dst.width + x) * dst.channels
			dst.data[dstIdx] = uint8(math.Round(rSum))
			dst.data[dstIdx+1] = uint8(math.Round(gSum))
			dst.data[dstIdx+2] = uint8(math.Round(bSum))
			dst.data[dstIdx+3] = uint8(math.Round(aSum))
		}

		// Process middle part (no boundary checks needed)
		for x := radius; x < src.width-radius; x++ {
			var rSum, gSum, bSum, aSum float64
			for k := -radius; k <= radius; k++ {
				sx := x + k
				idx := (y*src.width + sx) * src.channels
				weight := kernel[k+radius]

				rSum += float64(src.data[idx]) * weight
				gSum += float64(src.data[idx+1]) * weight
				bSum += float64(src.data[idx+2]) * weight
				aSum += float64(src.data[idx+3]) * weight
			}

			dstIdx := (y*dst.width + x) * dst.channels
			dst.data[dstIdx] = uint8(math.Round(rSum))
			dst.data[dstIdx+1] = uint8(math.Round(gSum))
			dst.data[dstIdx+2] = uint8(math.Round(bSum))
			dst.data[dstIdx+3] = uint8(math.Round(aSum))
		}

		// Process right edge (x >= width - radius)
		for x := src.width - radius; x < src.width; x++ {
			if x < radius {
				continue // Skip if already processed in left edge
			}

			var rSum, gSum, bSum, aSum float64

			for k := -radius; k <= radius; k++ {
				sx := x + k
				if sx >= src.width {
					sx = src.width - 1
				}

				idx := (y*src.width + sx) * src.channels
				weight := kernel[k+radius]

				rSum += float64(src.data[idx]) * weight
				gSum += float64(src.data[idx+1]) * weight
				bSum += float64(src.data[idx+2]) * weight
				aSum += float64(src.data[idx+3]) * weight
			}

			dstIdx := (y*dst.width + x) * dst.channels
			dst.data[dstIdx] = uint8(math.Round(rSum))
			dst.data[dstIdx+1] = uint8(math.Round(gSum))
			dst.data[dstIdx+2] = uint8(math.Round(bSum))
			dst.data[dstIdx+3] = uint8(math.Round(aSum))
		}
	}
}

// apply a separable Gaussian blur filter
func gaussianBlur(src image.Image, radius int, workers int) image.Image {
	bounds := src.Bounds()
	width := bounds.Max.X - bounds.Min.X
	height := bounds.Max.Y - bounds.Min.Y

	// Generate Gaussian kernel
	kernel := generateGaussianKernel(radius)

	// Convert to flat array for better performance
	srcData := &ImageData{
		data:     make([]uint8, width*height*4),
		width:    width,
		height:   height,
		channels: 4,
	}

	// Copy image data
	idx := 0
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r, g, b, a := src.At(x, y).RGBA()
			srcData.data[idx] = uint8(r >> 8)
			srcData.data[idx+1] = uint8(g >> 8)
			srcData.data[idx+2] = uint8(b >> 8)
			srcData.data[idx+3] = uint8(a >> 8)
			idx += 4
		}
	}

	// Allocate buffers
	dstHorizontal := &ImageData{
		data:     make([]uint8, len(srcData.data)),
		width:    width,
		height:   height,
		channels: 4,
	}

	// Phase 1: Horizontal blur
	var wg sync.WaitGroup
	rowsPerWorker := height / workers

	for i := range workers {
		startY := i * rowsPerWorker
		endY := startY + rowsPerWorker
		if i == workers-1 {
			endY = height
		}

		wg.Add(1)
		go func(start, end int) {
			defer wg.Done()
			horizontalGaussianBlur(srcData, dstHorizontal, kernel, radius, start, end)
		}(startY, endY)
	}
	wg.Wait()

	// Transpose for vertical pass
	dstHorizontalTransposed := transposeImage(dstHorizontal)

	// Allocate transposed destination
	dstVerticalTransposed := &ImageData{
		data:     make([]uint8, len(srcData.data)),
		width:    height, // Swapped
		height:   width,  // Swapped
		channels: 4,
	}

	// Phase 2: Vertical blur (on transposed data, so it's horizontal in memory)
	rowsPerWorker = width / workers

	for i := range workers {
		startY := i * rowsPerWorker
		endY := startY + rowsPerWorker
		if i == workers-1 {
			endY = width
		}

		wg.Add(1)
		go func(start, end int) {
			defer wg.Done()
			horizontalGaussianBlur(dstHorizontalTransposed, dstVerticalTransposed, kernel, radius, start, end)
		}(startY, endY)
	}
	wg.Wait()

	// Transpose back to original orientation
	dstFinal := transposeImage(dstVerticalTransposed)

	// Convert back to image
	dst := image.NewRGBA(image.Rect(0, 0, width, height))
	idx = 0
	for y := range height {
		for x := range width {
			dst.Set(x, y, color.RGBA{
				R: dstFinal.data[idx],
				G: dstFinal.data[idx+1],
				B: dstFinal.data[idx+2],
				A: dstFinal.data[idx+3],
			})
			idx += 4
		}
	}

	return dst
}

// loadImage loads an image from file using standard library
func loadImage(path string) (image.Image, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	// Decode based on file extension
	ext := strings.ToLower(filepath.Ext(path))
	switch ext {
	case ".jpg", ".jpeg":
		return jpeg.Decode(file)
	case ".png":
		return png.Decode(file)
	default:
		// Try auto-detection
		img, _, err := image.Decode(file)
		return img, err
	}
}

// saveImage saves an image to file
func saveImage(img image.Image, path string) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()

	ext := strings.ToLower(filepath.Ext(path))
	switch ext {
	case ".jpg", ".jpeg":
		return jpeg.Encode(file, img, &jpeg.Options{Quality: 95})
	case ".png":
		return png.Encode(file, img)
	default:
		return fmt.Errorf("unsupported format: %s", ext)
	}
}

func main() {
	args := os.Args

	if len(args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: %s <input_image> [output_image] [radius] [workers]\n", args[0])
		os.Exit(1)
	}

	inputPath := args[1]
	outputPath := "blurred.png"
	radius := 5
	workers := runtime.NumCPU()

	if len(args) > 2 {
		outputPath = args[2]
	}
	if len(args) > 3 {
		if r, err := strconv.Atoi(args[3]); err == nil {
			radius = r
		}
	}
	if len(args) > 4 {
		if w, err := strconv.Atoi(args[4]); err == nil {
			workers = w
		}
	}

	// Load image
	fmt.Printf("Loading image: %s\n", inputPath)
	loadStart := time.Now()
	img, err := loadImage(inputPath)
	if err != nil {
		log.Fatalf("Failed to load image: %v", err)
	}
	loadDuration := time.Since(loadStart)
	fmt.Printf("Image loaded in %v\n", loadDuration)

	// Get image dimensions
	bounds := img.Bounds()
	width := bounds.Max.X - bounds.Min.X
	height := bounds.Max.Y - bounds.Min.Y
	fmt.Printf("Image size: %dx%d\n", width, height)
	fmt.Printf("Applying Gaussian blur with radius %d using %d workers...\n", radius, workers)
	blurStart := time.Now()

	result := gaussianBlur(img, radius, workers)

	blurDuration := time.Since(blurStart)
	fmt.Printf("Blur processing completed in %v\n", blurDuration)

	// Save result
	fmt.Printf("Saving to: %s\n", outputPath)
	saveStart := time.Now()
	if err := saveImage(result, outputPath); err != nil {
		log.Fatalf("Failed to save image: %v", err)
	}
	saveDuration := time.Since(saveStart)
	fmt.Printf("Image saved in %v\n", saveDuration)

	totalDuration := time.Since(loadStart)
	fmt.Printf("Total time: %v\n", totalDuration)
	fmt.Println("Done!")
}
