#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/tests/build"
status=0
for tex in "$ROOT"/tests/*.tex; do
  name=$(basename "$tex" .tex)
  echo "==> $name"
  if ! TEXINPUTS="$ROOT:$ROOT/src//:" lualatex -interaction=nonstopmode -halt-on-error -file-line-error -output-directory="$ROOT/tests/build" "$tex" >"/tmp/${name}.log" 2>&1; then
    cat "/tmp/${name}.log"
    status=1
  fi
done
exit $status
