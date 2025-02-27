#!/usr/bin/env python

""" 1.2.1-clean-image.py """

import argparse
import sys

import numpy as np
import cv2


def parse_args(args):
    """Command-line interface"""

    argp = argparse.ArgumentParser(description="Image Cleaner")

    argp.add_argument("input", help="Path to the input image")
    argp.add_argument("output", help="Path to save the processed image")

    # Noise Reduction
    argp.add_argument(
        "--denoise_method",
        type=str,
        default="none",
        choices=["none", "fastNlMeans", "bilateral"],
        help="Noise reduction method to apply.",
    )
    argp.add_argument(
        "--fast_h", type=float, default=10.0, help="Strength for fastNlMeans denoising."
    )
    argp.add_argument(
        "--fast_hColor",
        type=float,
        default=10.0,
        help="Color component strength for fastNlMeans.",
    )
    argp.add_argument(
        "--fast_templateWindowSize",
        type=int,
        default=7,
        help="Template window size for fastNlMeans.",
    )
    argp.add_argument(
        "--fast_searchWindowSize",
        type=int,
        default=21,
        help="Search window size for fastNlMeans.",
    )
    argp.add_argument(
        "--bilateral_d", type=int, default=9, help="Diameter for bilateral filtering."
    )
    argp.add_argument(
        "--bilateral_sigmaColor",
        type=float,
        default=75.0,
        help="Sigma for color in bilateral filtering.",
    )
    argp.add_argument(
        "--bilateral_sigmaSpace",
        type=float,
        default=75.0,
        help="Sigma for space in bilateral filtering.",
    )

    # Contrast
    argp.add_argument(
        "--contrast_method",
        type=str,
        default="none",
        choices=["none", "clahe", "gamma"],
        help="Contrast enhancement method to apply.",
    )
    argp.add_argument(
        "--clahe_clipLimit", type=float, default=2.0, help="Clip limit for CLAHE."
    )
    argp.add_argument(
        "--clahe_tileSize",
        type=int,
        default=8,
        help="Tile grid size (square dimension) for CLAHE.",
    )
    argp.add_argument(
        "--gamma", type=float, default=1.0, help="Gamma value for gamma correction."
    )

    # Sharpening
    argp.add_argument(
        "--sharpen_method",
        type=str,
        default="none",
        choices=["none", "unsharp", "kernel"],
        help="Sharpening method to apply.",
    )
    argp.add_argument(
        "--unsharp_kernel",
        type=int,
        default=5,
        help="Kernel size for Gaussian blur in unsharp masking.",
    )
    argp.add_argument(
        "--unsharp_sigma",
        type=float,
        default=1.0,
        help="Sigma for Gaussian blur in unsharp masking.",
    )
    argp.add_argument(
        "--unsharp_amount",
        type=float,
        default=1.0,
        help="Amount to scale the unsharp mask effect.",
    )

    return argp.parse_args(args)


# Noise Reduction
def denoise_fastNlMeans(
    img, h=10, hColor=10, templateWindowSize=7, searchWindowSize=21
):
    """Apply fastNlMeansDenoising for colored images."""
    return cv2.fastNlMeansDenoisingColored(
        img, None, h, hColor, templateWindowSize, searchWindowSize
    )


def denoise_bilateral(img, d=9, sigmaColor=75, sigmaSpace=75):
    """Apply bilateral filtering to reduce noise while preserving edges."""
    return cv2.bilateralFilter(img, d, sigmaColor, sigmaSpace)


# Contrast
def enhance_contrast_CLAHE(img, clipLimit=2.0, tileGridSize=(8, 8)):
    """Enhance contrast using CLAHE in the LAB color space."""
    lab = cv2.cvtColor(img, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=clipLimit, tileGridSize=tileGridSize)
    l_enhanced = clahe.apply(l)
    lab_enhanced = cv2.merge((l_enhanced, a, b))
    return cv2.cvtColor(lab_enhanced, cv2.COLOR_LAB2BGR)


def enhance_contrast_gamma(img, gamma=1.0):
    """Apply gamma correction to adjust brightness."""
    invGamma = 1.0 / gamma
    table = np.array([((i / 255.0) ** invGamma) * 255 for i in np.arange(256)]).astype(
        "uint8"
    )
    return cv2.LUT(img, table)


# Sharpening
def sharpen_unsharp_mask(img, kernel_size=(5, 5), sigma=1.0, amount=1.0):
    """Enhance edges using unsharp masking."""
    blurred = cv2.GaussianBlur(img, kernel_size, sigma)
    sharpened = cv2.addWeighted(img, 1 + amount, blurred, -amount, 0)
    return sharpened


def sharpen_kernel(img):
    """Sharpen using a simple convolution kernel."""
    kernel = np.array([[0, -1, 0], [-1, 5, -1], [0, -1, 0]])
    return cv2.filter2D(img, -1, kernel)


def process_image(input_path, output_path, args):
    img = cv2.imread(input_path)
    if img is None:
        print("Error: Could not read the input image.")
        return

    result = img.copy()

    # --- Noise Reduction ---
    if args.denoise_method == "fastNlMeans":
        result = denoise_fastNlMeans(
            result,
            h=args.fast_h,
            hColor=args.fast_hColor,
            templateWindowSize=args.fast_templateWindowSize,
            searchWindowSize=args.fast_searchWindowSize,
        )
    elif args.denoise_method == "bilateral":
        result = denoise_bilateral(
            result,
            d=args.bilateral_d,
            sigmaColor=args.bilateral_sigmaColor,
            sigmaSpace=args.bilateral_sigmaSpace,
        )

    # --- Contrast Enhancement ---
    if args.contrast_method == "clahe":
        result = enhance_contrast_CLAHE(
            result,
            clipLimit=args.clahe_clipLimit,
            tileGridSize=(args.clahe_tileSize, args.clahe_tileSize),
        )
    elif args.contrast_method == "gamma":
        result = enhance_contrast_gamma(result, gamma=args.gamma)

    # --- Sharpening ---
    if args.sharpen_method == "unsharp":
        result = sharpen_unsharp_mask(
            result,
            kernel_size=(args.unsharp_kernel, args.unsharp_kernel),
            sigma=args.unsharp_sigma,
            amount=args.unsharp_amount,
        )
    elif args.sharpen_method == "kernel":
        result = sharpen_kernel(result)

    cv2.imwrite(output_path, result)
    print(f"Processed image saved to {output_path}")


def main(args):
    params = argp.parse_args(args)
    process_image(params.input, params.output, params)


if __name__ == "__main__":
    main(sys.argv[1:])
