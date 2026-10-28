#!/usr/bin/env bash
# Real AT-SPI verification: launches the release build inside a private
# D-Bus session with the real accessibility stack (at-spi-bus-launcher +
# at-spi2-registryd) and walks the exposed tree with pyatspi — the same
# client library Orca uses. Exits non-zero on contract failure.
#
# Requires: dbus-daemon, at-spi2-core, python3-pyatspi (or
#   PYTHONPATH pointing at an extracted pyatspi), DISPLAY.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="${APP:-build/linux/x64/release/bundle/quickgui}"
PYATSPI="${PYATSPI:-/tmp/pyatspi/usr/lib/python3/dist-packages}"

dbus-run-session -- bash -c "
  /usr/libexec/at-spi-bus-launcher --launch-immediately &
  sleep 1
  /usr/libexec/at-spi2-registryd &
  sleep 1
  '$APP' &
  APPPID=\$!
  sleep 6
  PYTHONPATH='$PYATSPI' python3 tool/atspi_walk.py quickgui
  RC=\$?
  kill \$APPPID 2>/dev/null || true
  exit \$RC
"
