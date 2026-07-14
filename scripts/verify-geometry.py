#!/usr/bin/env python3
import json
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


def page_blocks(pdf: Path, page: int) -> list[tuple[dict[str, str], str]]:
    xml = subprocess.run(
        ["pdftotext", "-f", str(page), "-l", str(page),
         "-bbox-layout", str(pdf), "-"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    root = ET.fromstring(xml)
    result = []
    for element in root.iter():
        if not element.tag.endswith("block"):
            continue
        words = [
            word.text or ""
            for word in element.iter()
            if word.tag.endswith("word")
        ]
        result.append((element.attrib, " ".join(words)))
    return result


def find_block(blocks, marker: str):
    for attributes, text in blocks:
        if marker in text:
            return {key.lower(): float(value) for key, value in attributes.items()}
    raise AssertionError(f"could not find {marker!r}")


def within(value: float, low: float, high: float, label: str) -> None:
    if not low <= value <= high:
        raise AssertionError(f"{label}={value:.3f}, expected {low}..{high}")


def main() -> int:
    if len(sys.argv) not in (2, 3):
        print("usage: verify-geometry.py PDF [REFERENCE.json]", file=sys.stderr)
        return 2
    pdf = Path(sys.argv[1])
    reference_path = Path(sys.argv[2]) if len(sys.argv) == 3 else (
        Path(__file__).resolve().parent.parent / "tests/reference/urp-v6-geometry.json"
    )
    reference = json.loads(reference_path.read_text())
    info = subprocess.run(
        ["pdfinfo", str(pdf)], check=True, capture_output=True, text=True
    ).stdout
    size = re.search(r"Page size:\s+([0-9.]+) x ([0-9.]+) pts", info)
    if not size or tuple(map(float, size.groups())) != tuple(reference["page_points"]):
        raise AssertionError("unexpected page size")

    first = page_blocks(pdf, 1)
    second = page_blocks(pdf, 2)
    abstract = find_block(first, "ABSTRACT")
    title = find_block(first, "Line-Level Transaction Regression")
    introduction = find_block(first, "Introduction")
    main = find_block(first, "LINESTART9001")
    stub = find_block(first, "Line Tester")
    continuation = find_block(second, "LINEEND9003")
    running_head = find_block(second, "Urology Research and Practice")

    anchors = reference["anchors"]
    within(abstract["xmin"], *anchors["abstract_x"]["range"], "abstract x")
    within(introduction["xmin"], *anchors["introduction_x"]["range"], "introduction x")
    within(main["xmin"], *anchors["main_left_x"]["range"], "page-1 main x")
    within(main["xmax"], *anchors["main_right_x"]["range"], "page-1 main right")
    within(stub["xmin"], *anchors["stub_x"]["range"], "stub x")
    within(continuation["xmin"], *anchors["native_left_x"]["range"], "native continuation x")
    within(
        abstract["ymin"] - title["ymax"],
        *anchors["title_to_abstract_y_gap"]["range"],
        "title-to-abstract gap",
    )
    within(running_head["ymin"], *anchors["running_head_y"]["range"], "running-head y")
    within(continuation["ymin"], *anchors["native_body_top_y"]["range"], "native body top")

    with tempfile.TemporaryDirectory(prefix="tnq-visual-") as temporary:
        prefix = Path(temporary) / "page"
        subprocess.run(
            ["pdftoppm", "-f", "1", "-l", "1", "-r", "144", "-png",
             "-singlefile", str(pdf), str(prefix)],
            check=True,
            capture_output=True,
        )
        image = Image.open(prefix.with_suffix(".png")).convert("RGB")
        panel = tuple(reference["colors"]["abstract_panel_rgb"])
        panel_points = [
            (x, y)
            for y in range(image.height)
            for x in range(image.width)
            if image.getpixel((x, y)) == panel
        ]
        panel_pixels = len(panel_points)
        if panel_pixels < reference["minimum_panel_pixels_at_144dpi"]:
            raise AssertionError(f"abstract panel has only {panel_pixels} reference-color pixels")
        scale = 144 / 72
        panel_left = min(x for x, _ in panel_points) / scale
        panel_top = min(y for _, y in panel_points) / scale
        panel_right = max(x for x, _ in panel_points) / scale
        within(panel_left, *reference["panel_left_points"], "panel left")
        within(panel_right, *reference["panel_right_points"], "panel right")
        within(
            abstract["ymin"] - panel_top,
            *reference["panel_label_top_gap_points"],
            "panel-to-label gap",
        )
        top_y = min(y for _, y in panel_points)
        row_widths = {}
        for x, y in panel_points:
            row_widths[y] = row_widths.get(y, 0) + 1
        corner_inset = max(row_widths.values()) - row_widths[top_y]
        if corner_inset < reference["minimum_rounded_corner_inset_pixels_at_144dpi"]:
            raise AssertionError(f"abstract panel top is not measurably rounded: inset={corner_inset}")
        x0, x1 = (round(value * scale) for value in reference["rail_x_points"])
        rail = tuple(reference["colors"]["rail_rgb"])
        rail_pixels = sum(
            1 for x in range(x0, x1 + 1) for y in range(image.height)
            if image.getpixel((x, y)) == rail
        )
        if rail_pixels < reference["minimum_rail_pixels_at_144dpi"]:
            raise AssertionError(f"page rail has only {rail_pixels} reference-color pixels")
    print(f"{pdf.name}: measured visual reference anchors, panel, and rail verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.CalledProcessError) as error:
        print(f"geometry verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
