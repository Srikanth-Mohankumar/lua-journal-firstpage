#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
rm -rf "$ROOT/tests/build"
mkdir -p "$ROOT/tests/build"
status=0
if rg -n '\\(newpage|twocolumn|finishfirstpage)' "$ROOT/examples" "$ROOT/tests" --glob '*.tex'; then
  echo "article source contains a forbidden page-control command"
  status=1
fi
for tex in "$ROOT"/tests/*.tex; do
  name=$(basename "$tex" .tex)
  echo "==> $name"
  if ! TEXINPUTS="$ROOT:$ROOT/src//:" lualatex -interaction=nonstopmode -halt-on-error -file-line-error -output-directory="$ROOT/tests/build" "$tex" >"/tmp/${name}.log" 2>&1; then
    cat "/tmp/${name}.log"
    status=1
  elif grep -Eq 'TNQ-INTEGRITY .*missing=[1-9]|TNQ-INTEGRITY .*duplicate=[1-9]|TNQ-INTEGRITY .*order=[1-9]|TNQ-WHATSIT .*missing=[1-9]|TNQ-WHATSIT .*duplicate=[1-9]|TNQ-WHATSIT .*order=[1-9]|TNQ-MARK .*missing=[1-9]|TNQ-MARK .*duplicate=[1-9]|TNQ-MARK .*order=[1-9]|TNQ-ORIGIN .*missing=[1-9]|TNQ-ORIGIN .*duplicate=[1-9]|TNQ-ORIGIN .*order=[1-9]|TNQ-WIDTH .*wrong=[1-9]|commit=no' "/tmp/${name}.log"; then
    echo "transaction accounting failure in $name"
    grep 'TNQ-ACCOUNT' "/tmp/${name}.log"
    status=1
  fi
  if grep -Eq 'late-abs-width=[1-9]' "/tmp/${name}.log"; then
    echo "post-commit native-width failure in $name"
    status=1
  fi
done

echo "==> 010-forced-rollback (expected failure)"
rollback_tex="$ROOT/tests/expected-failure/010-forced-rollback.tex"
if TEXINPUTS="$ROOT:$ROOT/src//:" lualatex -interaction=nonstopmode \
    -halt-on-error -file-line-error -output-directory="$ROOT/tests/build" \
    "$rollback_tex" >"/tmp/010-forced-rollback.log" 2>&1; then
  echo "forced rollback unexpectedly compiled successfully"
  status=1
fi
if ! grep -q 'TNQ-ACCOUNT tx=1 commit=no' /tmp/010-forced-rollback.log ||
   ! grep -q 'TNQ-TEST tx=1 rejected=forced' /tmp/010-forced-rollback.log ||
   ! grep -q 'TNQ-ROLLBACK main-preserved=yes stub-preserved=yes' /tmp/010-forced-rollback.log; then
  echo "forced rollback did not prove preservation of both originals"
  grep -E 'TNQ-(ACCOUNT|TEST|ROLLBACK)' /tmp/010-forced-rollback.log || true
  status=1
fi

for gate in 017-footnote-protocol-gate 018-tagged-pdf-protocol-gate; do
  echo "==> $gate (expected failure)"
  gate_tex="$ROOT/tests/expected-failure/$gate.tex"
  if TEXINPUTS="$ROOT:$ROOT/src//:" lualatex -interaction=nonstopmode \
      -halt-on-error -file-line-error -output-directory="$ROOT/tests/build" \
      "$gate_tex" >"/tmp/$gate.log" 2>&1; then
    echo "$gate unexpectedly compiled successfully"
    status=1
  fi
done
if ! grep -q 'Footnotes require a separate first-' \
    /tmp/017-footnote-protocol-gate.log; then
  echo "footnote ownership gate did not issue its protocol diagnostic"
  status=1
fi
if ! grep -q 'Tagged PDF/DocumentMetadata requires a separate transaction protocol' \
    /tmp/018-tagged-pdf-protocol-gate.log; then
  echo "tagged-PDF ownership gate did not issue its protocol diagnostic"
  status=1
fi

if ! grep -Eq 'TNQ-CROSS tx=1 paragraphs=[1-9]' "/tmp/005-line-level-crossing.log"; then
  echo "005-line-level-crossing did not split a paragraph between page 1 and its remainder"
  status=1
fi
if [[ $(pdfinfo "$ROOT/tests/build/006-long-abstract.pdf" | awk '/^Pages:/ {print $2}') -lt 3 ]]; then
  echo "006-long-abstract did not continue beyond page 2"
  status=1
fi

if ! grep -q 'TNQ-ACCOUNT tx=1 domain=stub input=31 page=31 tail=0' \
    /tmp/011-exact-stub-fit.log; then
  echo "011-exact-stub-fit no longer lands exactly on the first stub boundary"
  status=1
fi
if ! grep -q 'TNQ-ACCOUNT tx=1 domain=stub input=32 page=31 tail=1' \
    /tmp/012-stub-fit-plus-one.log; then
  echo "012-stub-fit-plus-one did not retain exactly one continuation line"
  status=1
fi
if ! grep -q 'TNQ-ACCOUNT tx=1 domain=main input=43 page=43 tail=0' \
    /tmp/013-exact-page-keywords-fit.log; then
  echo "013-exact-page-keywords-fit no longer ends exactly at page 1"
  status=1
fi
if ! grep -Eq 'TNQ-PAYLOAD tx=1 domain=main write=[1-9][0-9]* destination=[1-9][0-9]* other=[1-9][0-9]*' \
    /tmp/014-whatsit-ownership.log; then
  echo "014-whatsit-ownership did not account for all payload classes"
  status=1
fi
if [[ ! -f "$ROOT/tests/build/014-whatsit-ownership.tnqwrite" ]] ||
   [[ $(grep -c '^WRITEFIRST9704$' "$ROOT/tests/build/014-whatsit-ownership.tnqwrite" || true) -ne 1 ]] ||
   [[ $(grep -c '^WRITESECOND9705$' "$ROOT/tests/build/014-whatsit-ownership.tnqwrite" || true) -ne 1 ]]; then
  echo "014-whatsit-ownership delayed writes were not executed exactly once"
  status=1
fi

python3 "$ROOT/scripts/verify-tokens.py" "$ROOT/tests/build/005-line-level-crossing.pdf" \
  LINESTART9001 LINEMIDDLE9002 LINEEND9003 AFTERPAR9004 || status=1
python3 "$ROOT/scripts/verify-tokens.py" "$ROOT/tests/build/006-long-abstract.pdf" \
  ABSSTART9101 ABSEND9102 ABSKEY9103 INTROAFTER9104 || status=1
python3 "$ROOT/scripts/verify-tokens.py" "$ROOT/tests/build/007-long-stub.pdf" \
  STUBSTART9201 STUBEND9202 ARTICLESTART9203 ARTICLEEND9204 || status=1
python3 "$ROOT/scripts/verify-tokens.py" "$ROOT/tests/build/008-simultaneous-overflow.pdf" \
  COMBABSSTART9301 COMBABSEND9302 COMBKEY9303 STUBMID9304 \
  COMBSTUBSTART9305 COMBSTUBEND9306 COMBARTSTART9307 COMBARTEND9308 || status=1
python3 "$ROOT/scripts/verify-tokens.py" "$ROOT/tests/build/009-paragraph-list-handoff.pdf" \
  HANDOFFSTART9401 HANDOFFTAIL9402 LISTONE9403 LISTTWO9404 LISTTHREE9405 \
  AFTERLIST9406 RIGHTCOLUMN9407 || status=1
python3 "$ROOT/scripts/verify-tokens.py" "$ROOT/tests/build/011-exact-stub-fit.pdf" \
  EXACTSTUBSTART9601 EXACTSTUBEND9602 EXACTARTICLE9603 || status=1
python3 "$ROOT/scripts/verify-tokens.py" "$ROOT/tests/build/012-stub-fit-plus-one.pdf" \
  OVERSTUBSTART9611 OVERSTUBEND9612 OVERARTICLE9613 || status=1
python3 "$ROOT/scripts/verify-tokens.py" "$ROOT/tests/build/014-whatsit-ownership.pdf" \
  PAYLOADSTART9701 PAYLOADTAIL9702 PAYLOADEND9703 || status=1
python3 "$ROOT/scripts/verify-handoff.py" \
  "$ROOT/tests/build/009-paragraph-list-handoff.pdf" || status=1
python3 "$ROOT/scripts/verify-marks.py" \
  "$ROOT/tests/build/015-mark-handoff.pdf" || status=1
python3 "$ROOT/scripts/verify-boundaries.py" \
  "$ROOT/tests/build/013-exact-page-keywords-fit.pdf" || status=1
python3 "$ROOT/scripts/verify-headings.py" \
  "$ROOT/tests/build/016-heading-near-split.pdf" || status=1
python3 "$ROOT/scripts/verify-geometry.py" \
  "$ROOT/tests/build/005-line-level-crossing.pdf" || status=1
python3 "$ROOT/scripts/verify-published-profile.py" \
  "$ROOT/tests/build/019-published-reference-profile.pdf" || status=1
python3 "$ROOT/scripts/verify-determinism.py" "$ROOT" \
  "$ROOT/tests/014-whatsit-ownership.tex" || status=1
exit $status
