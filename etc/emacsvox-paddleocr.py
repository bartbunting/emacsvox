#!/usr/bin/env python3

# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
#
# This file is part of Emacsvox.

"""Convert an image or PDF to Markdown with PaddleOCR PP-StructureV3."""

from __future__ import annotations

import argparse
import contextlib
import os
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    """Parse command-line options."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", nargs="?", type=Path, help="image or PDF to recognize")
    parser.add_argument(
        "--check",
        action="store_true",
        help="check that PaddlePaddle and PaddleOCR can be imported, then exit",
    )
    parser.add_argument(
        "--lang",
        default=os.environ.get("EMACSVOX_PADDLEOCR_LANGUAGE", "en"),
        help="OCR language (default: en)",
    )
    parser.add_argument(
        "--device",
        default=os.environ.get("EMACSVOX_PADDLEOCR_DEVICE", "cpu"),
        help="Paddle device (default: cpu)",
    )
    parser.add_argument(
        "--enable-mkldnn",
        action="store_true",
        help="enable oneDNN/MKL-DNN CPU acceleration",
    )
    parser.add_argument(
        "--no-doc-orientation",
        action="store_false",
        dest="use_doc_orientation_classify",
        help="disable document orientation classification",
    )
    parser.add_argument(
        "--no-doc-unwarping",
        action="store_false",
        dest="use_doc_unwarping",
        help="disable document unwarping",
    )
    parser.add_argument(
        "--no-textline-orientation",
        action="store_false",
        dest="use_textline_orientation",
        help="disable text-line orientation classification",
    )
    parser.add_argument(
        "--no-tables",
        action="store_false",
        dest="use_table_recognition",
        help="disable table recognition",
    )
    parser.add_argument(
        "--no-formulas",
        action="store_false",
        dest="use_formula_recognition",
        help="disable formula recognition",
    )
    return parser.parse_args()


def import_paddleocr():
    """Import PaddleOCR while keeping its startup messages off stdout."""
    with contextlib.redirect_stdout(sys.stderr):
        import paddle  # pylint: disable=import-outside-toplevel
        import paddleocr  # pylint: disable=import-outside-toplevel
        from paddleocr import PPStructureV3  # pylint: disable=import-outside-toplevel

    return paddle, paddleocr, PPStructureV3


def main() -> int:
    """Run the requested check or document conversion."""
    args = parse_args()
    try:
        paddle, paddleocr, pipeline_class = import_paddleocr()
    except Exception as error:  # Package import failures vary by platform.
        print(f"Unable to load PaddleOCR: {error}", file=sys.stderr)
        return 2

    if args.check:
        print(
            f"PaddlePaddle {paddle.__version__}; "
            f"PaddleOCR {paddleocr.__version__}; device {args.device}"
        )
        return 0

    if args.input is None:
        print("An image or PDF input file is required.", file=sys.stderr)
        return 2

    input_path = args.input.expanduser().resolve()
    if not input_path.is_file():
        print(f"Input file does not exist: {input_path}", file=sys.stderr)
        return 2

    try:
        with contextlib.redirect_stdout(sys.stderr):
            pipeline = pipeline_class(
                lang=args.lang,
                device=args.device,
                enable_mkldnn=args.enable_mkldnn,
                use_doc_orientation_classify=args.use_doc_orientation_classify,
                use_doc_unwarping=args.use_doc_unwarping,
                use_textline_orientation=args.use_textline_orientation,
                use_table_recognition=args.use_table_recognition,
                use_formula_recognition=args.use_formula_recognition,
            )
            results = pipeline.predict(str(input_path))
            pages = [result.markdown for result in results]
            markdown = pipeline.concatenate_markdown_pages(pages)
        if isinstance(markdown, tuple):
            markdown = markdown[0]
        if not isinstance(markdown, str):
            markdown = markdown["markdown_texts"]
        print(markdown.rstrip())
    except Exception as error:  # Model and input errors have many concrete types.
        print(f"PaddleOCR failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
