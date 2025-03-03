#!/usr/bin/env python

""" 1.3.1-convert-pdf.py """

import argparse
import os
import subprocess
import sys


def run_tesseract(image_path, output_base, lang="eng"):
    """
    Run Tesseract on the image path to produce HOCR XML output.
    The output file will be named <output_base>.hocr.
    """
    tesseract_command = ["tesseract", image_path, output_base, "hocr", "-l", lang]

    print("Running Tesseract command:")
    print(" ".join(tesseract_command))
    subprocess.run(tesseract_command, check=True)
    print(f"Tesseract OCR completed, output: {output_base}.hocr")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("img_file", help="Path to the input image file")
    parser.add_argument(
        "--dpi",
        type=int,
        default=600,
        help="Resolution (dpi) for image conversion",
    )
    parser.add_argument(
        "--lang", default="eng", help="Language for Tesseract OCR (default: eng)"
    )
    parser.add_argument(
        "--output", default="output", help="Base filename for final output."
    )
    args = parser.parse_args()

    if not os.path.exists(args.image_file):
        print(f"Error: image file '{args.image_file}' not found.")
        sys.exit(1)

    run_tesseract(temp_tiff, args.output, lang=args.lang)


if __name__ == "__main__":
    main()
