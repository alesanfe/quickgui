#!/usr/bin/env bash
# Runs the full flutter test suite on Linux/WSL with quickemu on PATH so the
# real-CLI integration tests execute instead of skipping. Override via env:
#   FLUTTER_SDK=/path/to/sdk QUICKEMU_BIN=/path/to/quickemu/bin ./run_tests.sh
FLUTTER_SDK="${FLUTTER_SDK:-/home/alesanfe/flutter-sdk}"
QUICKEMU_BIN="${QUICKEMU_BIN:-/mnt/c/Users/alex0/Documents/fyp/quickemu/bin}"
export PATH="${QUICKEMU_BIN}:${FLUTTER_SDK}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
cd "$(dirname "$0")" || exit 1
flutter test "$@" 2>&1 | grep -vE "No translation was found"
echo "TEST_EXIT=${PIPESTATUS[0]}"
