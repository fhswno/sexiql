#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

DMGBUILD_VERSION="1.6.7"
DMGBUILD_MIN_PYTHON="3.10"
VENV="$PWD/build/dmg-venv"

if [ -x "$VENV/bin/dmgbuild" ]; then
  echo "dmgbuild $DMGBUILD_VERSION already installed"
  exit 0
fi

python_major_at_least() {
  "$1" - <<'PY' 2>/dev/null
import sys
raise SystemExit(0 if sys.version_info >= (3, 10) else 1)
PY
}

PYTHON_BIN=""
for candidate in python3 /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
  if command -v "$candidate" >/dev/null 2>&1 && python_major_at_least "$candidate"; then
    PYTHON_BIN="$candidate"
    break
  fi
done

if [ -z "$PYTHON_BIN" ]; then
  printf 'error: no python3 >= %s found (dmgbuild %s requires it)\n' \
    "$DMGBUILD_MIN_PYTHON" "$DMGBUILD_VERSION" >&2
  exit 1
fi

echo ">> Using $PYTHON_BIN ($("$PYTHON_BIN" --version 2>&1))"
rm -rf "$VENV"
"$PYTHON_BIN" -m venv "$VENV"
"$VENV/bin/pip" install --quiet "dmgbuild==$DMGBUILD_VERSION"

"$VENV/bin/dmgbuild" -h >/dev/null
echo "dmgbuild $DMGBUILD_VERSION installed: $VENV/bin/dmgbuild"
