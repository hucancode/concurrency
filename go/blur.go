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

// RowData represents processed pixel data for a row
type RowData struct {
	y      int
	pixels []color.RGBA
}

// boxBlur applies a box blur filter to an image using goroutines and channels
func boxBlur(src image.Image, radius int, workers int) image.Image {
	bounds := src.Bounds()
	width := bounds.Max.X - bounds.Min.X
	height := bounds.Max.Y - bounds.Min.Y
	
	// Create output image
	dst := image.NewRGBA(image.Rect(0, 0, width, height))
	
	// Create work channel and result channel
	workChan := make(chan WorkUnit, workers)
	resultChan := make(chan RowData, height)
	var wg sync.WaitGroup
	
	// Calculate kernel size
	kernelSize := 2*radius + 1
	kernelArea := kernelSize * kernelSize
	
	// Start worker goroutines
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for work := range workChan {
				processRegion(src, work.startY, work.endY, radius, kernelArea, resultChan)
			}
		}()
	}
	
	// Distribute work
	go func() {
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
	}()
	
	// Collector goroutine
	go func() {
		wg.Wait()
		close(resultChan)
	}()
	
	// Collect results and write to destination
	for rowData := range resultChan {
		for x, pixel := range rowData.pixels {
			dst.Set(x, rowData.y, pixel)
		}
	}
	
	return dst
}

// processRegion processes a horizontal strip of the image
func processRegion(src image.Image, startY, endY, radius, kernelArea int, resultChan chan<- RowData) {
	bounds := src.Bounds()
	minX := bounds.Min.X
	minY := bounds.Min.Y
	maxX := bounds.Max.X
	maxY := bounds.Max.Y
	width := maxX - minX
	height := maxY - minY
	
	for y := startY; y < endY; y++ {
		// Process entire row into buffer
		rowPixels := make([]color.RGBA, width)
		
		for x := 0; x < width; x++ {
			var rSum, gSum, bSum, aSum uint32
			
			// Calculate actual bounds to eliminate branch in inner loop
			yStart := max(0, y-radius)
			yEnd := min(height-1, y+radius)
			xStart := max(0, x-radius)
			xEnd := min(width-1, x+radius)
			
			// Pre-calculate pixel count
			validPixels := uint32((yEnd - yStart + 1) * (xEnd - xStart + 1))
			
			// Now we can iterate without boundary checks
			for ky := yStart; ky <= yEnd; ky++ {
				for kx := xStart; kx <= xEnd; kx++ {
					// Accumulate pixel values - no bounds check needed
					r, g, b, a := src.At(kx+minX, ky+minY).RGBA()
					rSum += r
					gSum += g
					bSum += b
					aSum += a
				}
			}
			
			// Average the accumulated values
			rowPixels[x] = color.RGBA{
				R: uint8(rSum / validPixels >> 8),
				G: uint8(gSum / validPixels >> 8),
				B: uint8(bSum / validPixels >> 8),
				A: uint8(aSum / validPixels >> 8),
			}
		}
		
		// Send completed row
		resultChan <- RowData{y: y, pixels: rowPixels}
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