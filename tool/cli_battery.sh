#!/usr/bin/env bash
# CLI battery — every operation the app can trigger, exercised through
# the raw quickemu CLI. Mirrors ui_backend_battery_test.dart 1:1 so the
# interface behaviour and the backend behaviour stay in lock-step.
# Usage: QEMU_ACCEL=tcg CPU_MODEL=qemu64 tool/cli_battery.sh [workdir]
set -u
DIR="${1:-$(mktemp -d /tmp/cli_battery_XXXX)}"
VM="battery"
CONF="$DIR/$VM.conf"
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); echo "ok   - $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
run() { quickemu "$@" >/dev/null 2>&1; }
state() { quickemu --vm "$CONF" --status --format json 2>/dev/null | grep -o '"state":"[a-z]*"' | head -1; }

mkdir -p "$DIR"; cd "$DIR"
printf 'guest_os="linux"\ndisk_img="disk.qcow2"\nram="256M"\ndisplay="none"\n' > "$CONF"
touch disk.qcow2

# ── stopped-state ops ─────────────────────────────────────────────────
state | grep -q stopped && ok "status stopped" || bad "status"
run --vm "$CONF" --list-json && ok "list-json" || bad "list-json"
run --capabilities --format json && ok "capabilities" || bad "capabilities"
run --vm "$CONF" --op-list --format json && ok "op-list" || bad "op-list"
run --vm "$CONF" --delete-plan --format json && ok "delete-plan" || bad "delete-plan"
run --vm "$CONF" --snapshot-tree --format json && ok "snapshot-tree" || bad "snapshot-tree"
run --vm "$CONF" --trash-list --format json && ok "trash-list" || bad "trash-list"
run --vm "$CONF" --backup-list --format json && ok "backup-list" || bad "backup-list"
run --vm "$CONF" --events 0 && ok "events" || bad "events"
run --inventory --format json && ok "inventory" || bad "inventory"
run --vm "$CONF" --inspect-conf --format json && ok "inspect-conf" || bad "inspect-conf"
run --host-info --format json && ok "host-info" || bad "host-info"
run --plugins && ok "plugins" || bad "plugins"
run --vm "$CONF" --migrate-conf && [ -f "$VM.toml" ] && ok "migrate-conf" || bad "migrate-conf"

# ── live VM ops (needs a bootable backend — qemu64+tcg or KVM) ─────────
quickemu --vm "$CONF" &
BOOT=$!; sleep "${BOOT_WAIT:-25}"
if state | grep -q running; then
  ok "start→running"
  run --vm "$CONF" --pause && sleep 1 && state | grep -q paused && ok "pause→paused" || bad "pause"
  run --vm "$CONF" --resume && sleep 1 && state | grep -q running && ok "resume→running" || bad "resume"
  quickemu --vm "$CONF" --monitor-cmd 'info status' 2>/dev/null | grep -q 'VM status' && ok "monitor-cmd" || bad "monitor-cmd"
  run --vm "$CONF" --send-keys 'ctrl-alt-delete' && ok "send-keys" || bad "send-keys"
  run --vm "$CONF" --type 'echo hi' && ok "type" || bad "type"
  run --vm "$CONF" --screenshot && ok "screenshot" || bad "screenshot"
  run --vm "$CONF" --stats --format json && ok "stats" || bad "stats"
  run --vm "$CONF" --snapshot-clone && ok "snapshot-clone" || bad "snapshot-clone"
  run --vm "$CONF" --kill && sleep 2 && state | grep -q stopped && ok "kill→stopped" || bad "kill"
else
  echo "skip - live ops (VM did not reach running — needs CPU_MODEL=qemu64 QEMU_ACCEL=tcg or KVM)"
fi

echo "── $PASS passed, $FAIL failed"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
