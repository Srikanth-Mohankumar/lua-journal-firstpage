#!/usr/bin/env python3
"""Rebuild independently and compare normalized PDF text and TNQ ledgers."""

import hashlib
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def build(root: Path, tex: Path, destination: Path) -> tuple[bytes, bytes]:
    env = os.environ.copy()
    env["TEXINPUTS"] = f"{root}:{root / 'src'}//:"
    env["max_print_line"] = "1000"
    output = ""
    command = [
        "lualatex", "-interaction=nonstopmode", "-halt-on-error",
        "-file-line-error", f"-output-directory={destination}", str(tex),
    ]
    for _ in range(2):
        result = subprocess.run(command, env=env, check=True, capture_output=True, text=True)
        output = result.stdout
    pdf = destination / f"{tex.stem}.pdf"
    text = subprocess.run(
        ["pdftotext", "-layout", str(pdf), "-"],
        check=True,
        capture_output=True,
    ).stdout
    normalized_text = b"\n".join(line.rstrip() for line in text.splitlines()).strip() + b"\n"
    ledger = "\n".join(
        line.strip()
        for line in output.splitlines()
        if line.startswith("[tnqjournal] TNQ-")
    ).encode() + b"\n"
    if not ledger.strip():
        raise AssertionError("no TNQ ledger records captured")
    return normalized_text, ledger


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: verify-determinism.py ROOT TEST.tex", file=sys.stderr)
        return 2
    root, tex = Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve()
    with tempfile.TemporaryDirectory(prefix="tnq-determinism-") as temporary:
        base = Path(temporary)
        first_dir, second_dir = base / "first", base / "second"
        first_dir.mkdir()
        second_dir.mkdir()
        first = build(root, tex, first_dir)
        second = build(root, tex, second_dir)
    if first != second:
        raise AssertionError(
            "independent rebuild mismatch: "
            f"text {digest(first[0])} != {digest(second[0])}; "
            f"ledger {digest(first[1])} != {digest(second[1])}"
        )
    print(f"deterministic text sha256={digest(first[0])}")
    print(f"deterministic ledger sha256={digest(first[1])}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.CalledProcessError) as error:
        print(f"determinism verification failed: {error}", file=sys.stderr)
        raise SystemExit(1)
