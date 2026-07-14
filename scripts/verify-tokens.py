#!/usr/bin/env python3
import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: verify-tokens.py PDF TOKEN [TOKEN ...]", file=sys.stderr)
        return 2
    pdf = Path(sys.argv[1])
    text = subprocess.run(
        ["pdftotext", str(pdf), "-"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    failed = False
    for token in sys.argv[2:]:
        count = text.count(token)
        if count != 1:
            print(f"{pdf.name}: {token} occurs {count} times (expected 1)")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
