#!/usr/bin/env python3
"""Verify the measured page-one metadata terminator and native handoff."""

import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def marker(pdf: Path, page: int, token: str) -> tuple[float, float] | None:
    xml = subprocess.run(
        ["pdftotext", "-f", str(page), "-l", str(page), "-bbox", str(pdf), "-"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    root = ET.fromstring(xml)
    for word in root.iter():
        if word.tag.endswith("word") and word.text == token:
            return float(word.attrib["xMin"]), float(word.attrib["yMin"])
    return None


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify-boundaries.py PDF", file=sys.stderr)
        return 2
    pdf = Path(sys.argv[1])
    keyword = marker(pdf, 1, "EXACTKEYWORDS9623")
    introduction = marker(pdf, 2, "EXACTINTRO9624")
    if keyword is None:
        raise AssertionError("keyword terminator is not on page 1")
    if introduction is None:
        raise AssertionError("article handoff is not on page 2")
    if not 640 <= keyword[1] <= 725:
        raise AssertionError(f"keyword boundary y={keyword[1]:.2f} is not in the measured bottom band")
    if not keyword[0] < 420 and introduction[0] < 300:
        raise AssertionError("metadata/main-column positions are incorrect")
    print(f"{pdf.name}: exact page-1 abstract/keyword boundary verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.CalledProcessError) as error:
        print(f"boundary verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
