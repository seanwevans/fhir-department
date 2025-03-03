#!/usr/bin/env python

""" 1.3.1-convert-pdf.py """

import argparse
import os
import subprocess
import sys


def check_text_layer_and_extract(pdf_file, output_file):
    """
    Check if the PDF has a text layer by using pdftotext.
    If text is extracted (i.e. non-empty), write it to output_file and return True.
    Otherwise, return False.
    """
    tmp_text = "temp_text.txt"
    try:
        subprocess.run(["pdftotext", pdf_file, tmp_text], check=True)
        with open(tmp_text, "r", encoding="utf-8") as f:
            text = f.read().strip()
        if text:
            with open(output_file, "w", encoding="utf-8") as f:
                f.write(text)
            return True
        else:
            return False
    finally:
        if os.path.exists(tmp_text):
            os.remove(tmp_text)


def pdf_to_tiff(pdf_path, tiff_path, dpi=600):
    """
    Convert a PDF into a single multipage TIFF using Ghostscript.
    """
    gs_command = [
        "gs",
        "-q",  # Quiet mode
        "-dNOPAUSE",  # No pause after each page
        "-dBATCH",  # Exit after processing
        "-sDEVICE=tiff24nc",  # 24-bit color multipage TIFF
        f"-r{dpi}",
        f"-sOutputFile={tiff_path}",
        pdf_path,
    ]
    print("Running Ghostscript command:")
    print(" ".join(gs_command))
    subprocess.run(gs_command, check=True)
    print(f"PDF converted to TIFF: {tiff_path}")


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
    parser = argparse.ArgumentParser(
        description="If the PDF contains a text layer, extract it. Otherwise, convert the PDF to a multipage TIFF and perform OCR with Tesseract to produce a single HOCR XML output."
    )
    parser.add_argument("pdf_file", help="Path to the input PDF file")
    parser.add_argument(
        "--dpi",
        type=int,
        default=600,
        help="Resolution (dpi) for TIFF conversion (default: 600)",
    )
    parser.add_argument(
        "--lang", default="eng", help="Language for Tesseract OCR (default: eng)"
    )
    parser.add_argument(
        "--output",
        default="output",
        help="Base filename for final output. If a text layer exists, the extracted text is saved here; if OCR is used, Tesseract produces <output>.hocr (default: output)",
    )
    args = parser.parse_args()

    if not os.path.exists(args.pdf_file):
        print(f"Error: PDF file '{args.pdf_file}' not found.")
        sys.exit(1)

    print("Checking for an existing text layer in the PDF...")
    if check_text_layer_and_extract(args.pdf_file, args.output):
        print(f"Text layer found. Extracted text saved as '{args.output}'.")
        sys.exit(0)

    # No text layer found; perform OCR
    temp_tiff = "temp.tiff"
    try:
        pdf_to_tiff(args.pdf_file, temp_tiff, dpi=args.dpi)
        run_tesseract(temp_tiff, args.output, lang=args.lang)
    finally:
        if os.path.exists(temp_tiff):
            try:
                os.remove(temp_tiff)
                print(f"Temporary TIFF file '{temp_tiff}' removed.")
            except:
                pass


if __name__ == "__main__":
    main()
