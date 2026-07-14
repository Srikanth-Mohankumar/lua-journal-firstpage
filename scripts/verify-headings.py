#!/usr/bin/env python3
"""Ensure headings near page/column boundaries retain their first body line."""

import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def locate(pdf: Path, token: str, pages: int) -> tuple[int, float, float]:
    for page in range(1, pages + 1):
        xml = subprocess.run(
            ["pdftotext", "-f", str(page), "-l", str(page), "-bbox", str(pdf), "-"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        root = ET.fromstring(xml)
        for word in root.iter():
            if word.tag.endswith("word") and word.text == token:
                return page, float(word.attrib["xMin"]), float(word.attrib["yMin"])
    raise AssertionError(f"missing {token}")


def same_lane(heading, body, label: str) -> None:
    hp, hx, hy = heading
    bp, bx, by = body
    if hp != bp or (hx < 300) != (bx < 300):
        raise AssertionError(f"{label} was detached across a page or column")
    if not hy < by < hy + 55:
        raise AssertionError(f"{label} body is not immediately below its heading")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify-headings.py PDF", file=sys.stderr)
        return 2
    pdf = Path(sys.argv[1])
    info = subprocess.run(["pdfinfo", str(pdf)], check=True, capture_output=True, text=True).stdout
    match = re.search(r"^Pages:\s+(\d+)", info, re.MULTILINE)
    pages = int(match.group(1)) if match else 0
    same_lane(locate(pdf, "SPLITHEADING9821", pages),
              locate(pdf, "HEADINGBODY9822", pages), "transaction heading")
    same_lane(locate(pdf, "NATIVEHEADING9823", pages),
              locate(pdf, "NATIVEBODY9824", pages), "native heading")
    print(f"{pdf.name}: headings retained their first body lines")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.CalledProcessError) as error:
        print(f"heading verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
