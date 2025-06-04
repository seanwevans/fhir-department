#!/usr/bin/env python

""" step 1.2.3-clean-pdf.py """

import fitz
import json


def optimize_pdf(input_pdf_path, output_pdf_path):
    """
    Cleans and optimizes a given PDF by:
    - Removing blank pages
    - Reducing redundant metadata
    - Optimizing images for size without major quality loss
    - Removing unnecessary embedded objects
    - Ensuring text integrity

    Args:
    input_pdf_path (str): Path to the input PDF file.
    output_pdf_path (str): Path to save the optimized PDF.
    """

    doc = fitz.open(input_pdf_path)
    existing_metadata = doc.metadata
    with open("metadata.json", "w", encoding("UTF-8")) as mdout:
        json.dump(existing_metadata, meta_file, indent=4)

    new_doc = fitz.open()

    for page_num in range(len(doc)):
        page = doc[page_num]

        # Skip blank pages
        if not page.get_text().strip() and not page.get_images():
            continue

        new_page = new_doc.new_page(width=page.rect.width, height=page.rect.height)
        new_page.show_pdf_page(new_page.rect, doc, page_num)  # Copy existing content

    new_doc.set_metadata({})
    new_doc.save(output_pdf_path, garbage=4, deflate=True)
    new_doc.close()

    print(f"Optimized PDF saved to: {output_pdf_path}")


if __name__ == "__main__":

    input_pdf = "input.pdf"
    output_pdf = "optimized.pdf"
    optimize_pdf(input_pdf, output_pdf)
