#!/usr/bin/env python3
"""Validate the page-2 running header assembled from a custom mark class."""

import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify-marks.py PDF", file=sys.stderr)
        return 2
    text = subprocess.run(
        ["pdftotext", "-f", "2", "-l", "2", "-layout", sys.argv[1], "-"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.replace(" ", "").replace("\n", "")
    expected = (
        "MARKTOP9811-PAGEONE9801"
        "MARKFIRST9812-PAGETWO9802"
        "MARKLAST9813-PAGETWO9802"
    )
    if expected not in text:
        raise AssertionError(f"unexpected normalized page-2 running head: {text[:240]}")
    print(f"{Path(sys.argv[1]).name}: LaTeX mark-class running head verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.CalledProcessError) as error:
        print(f"mark verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
