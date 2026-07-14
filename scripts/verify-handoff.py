#!/usr/bin/env python3
"""Check the semantic tail/list handoff and normal page-2 column filling."""

import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def words(pdf: Path, page: int) -> dict[str, tuple[float, float]]:
    xml = subprocess.run(
        ["pdftotext", "-f", str(page), "-l", str(page), "-bbox", str(pdf), "-"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    root = ET.fromstring(xml)
    result: dict[str, tuple[float, float]] = {}
    for node in root.iter():
        if node.tag.endswith("word") and node.text:
            result[node.text] = (float(node.attrib["xMin"]), float(node.attrib["yMin"]))
    return result


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify-handoff.py PDF", file=sys.stderr)
        return 2
    positions = words(Path(sys.argv[1]), 2)
    required = ["HANDOFFTAIL9402", "LISTONE9403", "AFTERLIST9406", "RIGHTCOLUMN9407"]
    missing = [marker for marker in required if marker not in positions]
    if missing:
        raise AssertionError(f"page 2 lacks markers: {', '.join(missing)}")

    tail_x, tail_y = positions["HANDOFFTAIL9402"]
    list_x, list_y = positions["LISTONE9403"]
    after_x, after_y = positions["AFTERLIST9406"]
    right_x, _ = positions["RIGHTCOLUMN9407"]
    if not (tail_x < 300 and list_x < 300 and after_x < 300):
        raise AssertionError("paragraph tail, list, and following section must start in page-2 left column")
    if not tail_y < list_y < after_y:
        raise AssertionError("paragraph tail, list, and following section are out of source order")
    if right_x < 300:
        raise AssertionError("page-2 right column was not filled with subsequent article material")
    print("paragraph/list handoff and page-2 two-column fill verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.CalledProcessError) as error:
        print(f"handoff verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
