#!/usr/bin/env bash
export PATH="/home/alesanfe/flutter-sdk/bin:/usr/local/bin:/usr/bin:/bin"
cd /home/alesanfe/quickgui || exit 1
python3 /mnt/c/Users/alex0/Documents/fyp/quickgui/gen_manifest.py
cp /mnt/c/Users/alex0/Documents/fyp/quickgui/assets/capabilities/capability_manifest.json assets/capabilities/
dart run tool/generate_capability_matrix.dart
cp docs/capability_matrix.md /mnt/c/Users/alex0/Documents/fyp/quickgui/docs/
dart analyze lib/capabilities test/capabilities tool/generate_capability_matrix.dart
echo "=== tests ==="
flutter test test/capabilities/ 2>&1 | tail -40
