#!/usr/bin/env python3
"""Verify the measured one-page profile derived from the supplied publication."""

import json
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image


def run(*command: str) -> str:
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def within(value: float, limits: list[float], label: str) -> None:
    if not limits[0] <= value <= limits[1]:
        raise AssertionError(f"{label}={value:.3f}, expected {limits[0]}..{limits[1]}")


def bbox(points: list[tuple[int, int]], label: str) -> tuple[int, int, int, int]:
    if not points:
        raise AssertionError(f"no pixels found for {label}")
    return (
        min(x for x, _ in points), min(y for _, y in points),
        max(x for x, _ in points), max(y for _, y in points),
    )


def region_bbox(image: Image.Image, area: tuple[int, int, int, int], predicate, label: str):
    x0, y0, x1, y1 = area
    return bbox([
        (x, y) for y in range(y0, min(y1, image.height))
        for x in range(x0, min(x1, image.width)) if predicate(image.getpixel((x, y)))
    ], label)


def blocks(pdf: Path) -> list[tuple[dict[str, float], str]]:
    xml = run("pdftotext", "-f", "1", "-l", "1", "-bbox-layout", str(pdf), "-")
    root = ET.fromstring(xml)
    result = []
    for element in root.iter():
        if element.tag.endswith("block"):
            words = [word.text or "" for word in element.iter() if word.tag.endswith("word")]
            result.append((
                {key.lower(): float(value) for key, value in element.attrib.items()},
                " ".join(words),
            ))
    return result


def find(items, marker: str):
    for attributes, text in items:
        if marker in text:
            return attributes
    raise AssertionError(f"could not find profile text {marker!r}")


def verify_darken_resource(pdf: Path) -> None:
    pages = run("mutool", "show", str(pdf), "pages")
    page_match = re.search(r"page 1 = (\d+) 0 R", pages)
    if not page_match:
        raise AssertionError("could not resolve page object")
    page = run("mutool", "show", str(pdf), page_match.group(1))
    resource_match = re.search(r"/Resources (\d+) 0 R", page)
    content_match = re.search(r"/Contents (\d+) 0 R", page)
    if not resource_match or not content_match:
        raise AssertionError("could not resolve page resources and contents")
    resources = run("mutool", "show", str(pdf), resource_match.group(1))
    contents = run("mutool", "show", str(pdf), content_match.group(1))
    if "/TNQDarken" not in resources or "/BM /Darken" not in resources:
        raise AssertionError("abstract panel lacks its non-erasing Darken graphics state")
    if "/TNQDarken gs" not in contents:
        raise AssertionError("abstract line decorations do not activate Darken blending")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify-published-profile.py PDF", file=sys.stderr)
        return 2
    pdf = Path(sys.argv[1])
    root = Path(__file__).resolve().parent.parent
    reference = json.loads((root / "tests/reference/urp-v6-geometry.json").read_text())
    profile = reference["published_profile"]

    info = run("pdfinfo", str(pdf))
    if not re.search(r"^Pages:\s+1$", info, re.MULTILINE):
        raise AssertionError("published profile must commit to exactly one page")

    items = blocks(pdf)
    anchors = profile["anchors"]
    checks = [
        ("ORIGINAL ARTICLE", "ymin", "meta_y"),
        ("Transurethral Bipolar Enucleation", "ymin", "title_y"),
        ("ABSTRACT", "ymin", "abstract_y"),
        ("Introduction", "ymin", "introduction_y"),
        ("Ahmed G Mohamed", "xmin", "author_x"),
        ("Ahmed G Mohamed", "ymin", "author_y"),
        ("Department of Urology", "ymin", "details_y"),
        ("Corresponding author", "ymin", "correspondence_y"),
        ("Received:", "ymin", "dates_y"),
        ("Cite this article as:", "ymin", "citation_y"),
        ("Cite this article as:", "ymax", "citation_bottom"),
    ]
    for marker, coordinate, key in checks:
        within(find(items, marker)[coordinate], anchors[key], f"{marker} {coordinate}")

    layout = run("pdftotext", "-layout", str(pdf), "-")
    required_lines = [
        "Transurethral Bipolar Enucleation vs. Transurethral",
        "Monopolar Enucleation of the Prostate for the",
        "Treatment of Bladder Outlet Obstruction Due",
        "to Benign Prostatic Hyperplasia",
        "Cite this article as: Mohamed AG, Sayed O,",
        "tud.2026.25075.",
    ]
    for line in required_lines:
        if line not in layout:
            raise AssertionError(f"missing measured line break: {line!r}")

    verify_darken_resource(pdf)
    with tempfile.TemporaryDirectory(prefix="tnq-published-") as temporary:
        prefix = Path(temporary) / "page"
        subprocess.run([
            "pdftoppm", "-f", "1", "-l", "1", "-r", str(profile["raster_dpi"]),
            "-png", "-singlefile", str(pdf), str(prefix),
        ], check=True, capture_output=True)
        image = Image.open(prefix.with_suffix(".png")).convert("RGB")
        if list(image.size) != profile["rendered_page_pixels"]:
            raise AssertionError(f"unexpected raster size {image.size}")

        panel_color = tuple(reference["colors"]["abstract_panel_rgb"])
        dark_color = (44, 46, 53)
        blue = tuple(reference["colors"]["rail_rgb"])
        panel = region_bbox(image, (130, 400, 880, 1150), lambda c: c == panel_color, "panel")
        logo = region_bbox(image, (130, 70, 600, 230), lambda c: sum(c) < 700, "logo")
        rail = region_bbox(image, (80, 0, 110, image.height), lambda c: c == blue, "rail")
        badge = region_bbox(image, (135, 1480, 240, 1580), lambda c: sum(c) < 650, "badge")

        for measured, key in [(panel, "panel_bbox_pixels"), (logo, "logo_bbox_pixels")]:
            expected = profile[key]
            for value, name in zip(measured, ("x", "y", "right", "bottom")):
                within(value, expected[name], f"{key} {name}")
        for value, name in zip((rail[0], rail[2]), ("x", "right")):
            within(value, profile["rail_bbox_pixels"][name], f"rail {name}")
        for value, name in zip(badge, ("x", "y", "right", "bottom")):
            within(value, profile["badge_bbox_pixels"][name], f"badge {name}")

        rule_rows = [
            y for y in range(1580, image.height)
            if sum(image.getpixel((x, y)) == blue for x in range(1100, 1210)) >= 30
        ]
        within(min(rule_rows), profile["page_rule_y_pixels"], "page-rule top")
        number = region_bbox(
            image, (1150, 1592, 1195, 1614), lambda c: sum(c) < 550, "page number"
        )
        within(number[1], profile["page_number_y_pixels"]["top"], "page-number top")
        within(number[3], profile["page_number_y_pixels"]["bottom"], "page-number bottom")

        panel_ink = 0
        exact_dark = 0
        for y in range(panel[1], panel[3] + 1):
            for x in range(panel[0], panel[2] + 1):
                color = image.getpixel((x, y))
                if color != panel_color and sum(color) < 650:
                    panel_ink += 1
                if color == dark_color:
                    exact_dark += 1
        if panel_ink < profile["minimum_panel_ink_pixels"]:
            raise AssertionError(f"abstract ink loss or baseline repainting: {panel_ink} pixels")
        if exact_dark < profile["minimum_exact_dark_panel_pixels"]:
            raise AssertionError(f"abstract dark-glyph coverage is too low: {exact_dark} pixels")

    print(f"{pdf.name}: published page-1 logo, panel, baselines, lanes, footer, and line breaks verified")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.CalledProcessError) as error:
        print(f"published-profile verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
