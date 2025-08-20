package main

import (
	"fmt"
	"image"
	_ "image/jpeg" // Register JPEG decoder
	"image/png"
	"os"
	"runtime"
	"strconv"
	"time"
)

func loadImage(path string) (image.Image, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	img, _, err := image.Decode(file)
	if err != nil {
		return nil, err
	}

	return img, nil
}

func saveImage(path string, img image.Image) error {
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()

	return png.Encode(file, img)
}

func printUsage(program string) {
	fmt.Fprintf(os.Stderr, "Usage: %s <operation> <input_image> <output_image> <radius> <workers>\n", program)
	fmt.Fprintf(os.Stderr, "  operation: 'blur' or 'kuwahara'\n")
}

func main() {
	if len(os.Args) != 6 {
		printUsage(os.Args[0])
		os.Exit(1)
	}

	operation := os.Args[1]
	inputPath := os.Args[2]
	outputPath := os.Args[3]
	radius, err := strconv.Atoi(os.Args[4])
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid radius: %v\n", err)
		os.Exit(1)
	}
	numWorkers, err := strconv.Atoi(os.Args[5])
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid number of workers: %v\n", err)
		os.Exit(1)
	}

	if numWorkers <= 0 {
		numWorkers = runtime.NumCPU()
	}

	start := time.Now()
	srcImg, err := loadImage(inputPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to load image: %v\n", err)
		os.Exit(1)
	}
	loadTime := time.Since(start)

	bounds := srcImg.Bounds()
	fmt.Printf("Image loaded: %dx%d pixels\n", bounds.Max.X, bounds.Max.Y)
	fmt.Printf("Load time: %dms\n", loadTime.Milliseconds())

	var dstImg *image.RGBA
	start = time.Now()
	
	switch operation {
	case "blur":
		fmt.Printf("Applying Gaussian blur with radius %d using %d workers\n", radius, numWorkers)
		dstImg = applyGaussianBlur(srcImg, radius, numWorkers)
	case "kuwahara":
		fmt.Printf("Applying Kuwahara filter with radius %d using %d workers\n", radius, numWorkers)
		dstImg = applyKuwaharaFilter(srcImg, radius, numWorkers)
	default:
		fmt.Fprintf(os.Stderr, "Unknown operation: %s. Use 'blur' or 'kuwahara'\n", operation)
		os.Exit(1)
	}
	
	filterTime := time.Since(start)
	fmt.Printf("Filter time: %dms\n", filterTime.Milliseconds())

	start = time.Now()
	if err := saveImage(outputPath, dstImg); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to save image: %v\n", err)
		os.Exit(1)
	}
	saveTime := time.Since(start)

	fmt.Printf("Save time: %dms\n", saveTime.Milliseconds())
	fmt.Printf("Total time: %dms\n", (loadTime + filterTime + saveTime).Milliseconds())
}