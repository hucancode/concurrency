package main

import (
	"fmt"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"log"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

// WorkUnit represents a chunk of work for parallel processing
type WorkUnit struct {
	startY int
	endY   int
}

// boxBlur applies a box blur filter to an image using goroutines and channels
func boxBlur(src image.Image, radius int, workers int) image.Image {
	bounds := src.Bounds()
	width := bounds.Max.X - bounds.Min.X
	height := bounds.Max.Y - bounds.Min.Y

	// Create output image
	dst := image.NewRGBA(image.Rect(0, 0, width, height))

	// Create work channel and result sync
	workChan := make(chan WorkUnit, workers)
	var wg sync.WaitGroup

	// Calculate kernel size and normalization factor
	kernelSize := 2*radius + 1
	kernelArea := kernelSize * kernelSize

	// Start worker goroutines
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for work := range workChan {
				processRegion(src, dst, work.startY, work.endY, radius, kernelArea)
			}
		}()
	}

	// Distribute work
	rowsPerWorker := height / workers
	for i := 0; i < workers; i++ {
		startY := i * rowsPerWorker
		endY := startY + rowsPerWorker
		if i == workers-1 {
			endY = height
		}
		workChan <- WorkUnit{startY: startY, endY: endY}
	}
	close(workChan)

	// Wait for all workers to complete
	wg.Wait()

	return dst
}

// processRegion processes a horizontal strip of the image
func processRegion(src image.Image, dst *image.RGBA, startY, endY, radius, kernelArea int) {
	bounds := src.Bounds()
	minX := bounds.Min.X
	minY := bounds.Min.Y
	maxX := bounds.Max.X
	maxY := bounds.Max.Y

	for y := startY; y < endY; y++ {
		for x := 0; x < maxX-minX; x++ {
			var rSum, gSum, bSum, aSum uint32
			validPixels := 0

			// Apply kernel
			for ky := -radius; ky <= radius; ky++ {
				for kx := -radius; kx <= radius; kx++ {
					// Calculate source coordinates with bounds checking
					srcX := x + kx + minX
					srcY := y + ky + minY

					// Skip out-of-bounds pixels
					if srcX < minX || srcX >= maxX || srcY < minY || srcY >= maxY {
						continue
					}

					// Accumulate pixel values
					r, g, b, a := src.At(srcX, srcY).RGBA()
					rSum += r
					gSum += g
					bSum += b
					aSum += a
					validPixels++
				}
			}

			// Average the accumulated values
			if validPixels > 0 {
				dst.Set(x, y, color.RGBA{
					R: uint8(rSum / uint32(validPixels) >> 8),
					G: uint8(gSum / uint32(validPixels) >> 8),
					B: uint8(bSum / uint32(validPixels) >> 8),
					A: uint8(aSum / uint32(validPixels) >> 8),
				})
			}
		}
	}
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
	img, err := loadImage(inputPath)
	if err != nil {
		log.Fatalf("Failed to load image: %v", err)
	}

	// Apply blur
	fmt.Printf("Applying box blur with radius %d using %d workers...\n", radius, workers)
	start := time.Now()

	result := boxBlur(img, radius, workers)

	duration := time.Since(start)
	fmt.Printf("Blur completed in %v\n", duration)

	// Save result
	fmt.Printf("Saving to: %s\n", outputPath)
	if err := saveImage(result, outputPath); err != nil {
		log.Fatalf("Failed to save image: %v", err)
	}

	fmt.Println("Done!")
}
