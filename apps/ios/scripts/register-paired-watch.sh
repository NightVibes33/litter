#!/usr/bin/env bash
# Register a paired Apple Watch with Apple's Developer Portal so the
# CLI-driven build flow can install LitterWatch on the watch without
# Xcode's GUI involvement.
#
# When a fresh watch is paired with the Mac, Apple's developer profile
# doesn't yet include its UDID — `xcodebuild` will produce a successful
# build but `devicectl ... install app` then fails with "App could not
# be installed at this time" and nothing useful in the device log. The
# fix is one targeted xcodebuild invocation with
# `-allowProvisioningDeviceRegistration`, which prompts Xcode to add the
# UDID to the team's device list and refresh the provisioning profile.
#
# Discovery: `xcrun devicectl list devices --json-output` is queried for
# paired devices with `hardwareProperties.platform == "watchOS"`. If
# auto-discovery fails (watch unreachable, devicectl misbehaving, etc.)
# pass the UDID explicitly via `WATCH_UDID=<udid>`.
#
# Usage:
#   ./apps/ios/scripts/register-paired-watch.sh             # discover + register
#   WATCH_UDID=00008301-... ./apps/ios/scripts/register-paired-watch.sh
#   ./apps/ios/scripts/register-paired-watch.sh --dry-run   # print UDID, do not run xcodebuild
#   ./apps/ios/scripts/register-paired-watch.sh --print-udid
#
# Outputs the discovered UDID to stdout and (unless --dry-run) runs:
#   xcodebuild -project apps/ios/Litter.xcodeproj \
#     -scheme LitterWatch \
#     -destination "platform=watchOS,id=$WATCH_UDID" \
#     -allowProvisioningUpdates \
#     -allowProvisioningDeviceRegistration \
#     build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_PATH="$IOS_DIR/Litter.xcodeproj"
WATCH_SCHEME="${WATCH_SCHEME:-LitterWatch}"
XCODE_CONFIG="${XCODE_CONFIG:-Debug}"

DRY_RUN=0
PRINT_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --print-udid)
            PRINT_ONLY=1
            shift
            ;;
        -h|--help)
            sed -n '1,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            echo "usage: $(basename "$0") [--dry-run|--print-udid]" >&2
            exit 1
            ;;
    esac
done

discover_watch_udid() {
    local override="${WATCH_UDID:-}"
    if [[ -n "$override" ]]; then
        printf '%s' "$override"
        return 0
    fi

    if ! command -v xcrun >/dev/null 2>&1; then
        return 1
    fi

    local tmp
    tmp="$(mktemp -t register-paired-watch.XXXXXX.json)"
    trap 'rm -f "$tmp"' RETURN

    if ! xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1; then
        return 1
    fi

    python3 - "$tmp" <<'PY'
import json, os, sys

path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(1)
try:
    with open(path) as fh:
        payload = json.load(fh)
except (OSError, json.JSONDecodeError):
    sys.exit(1)

watches = []
for device in payload.get("result", {}).get("devices", []):
    hw = device.get("hardwareProperties", {}) or {}
    conn = device.get("connectionProperties", {}) or {}
    props = device.get("deviceProperties", {}) or {}
    if (hw.get("platform") or "").lower() != "watchos":
        continue
    if (conn.get("pairingState") or "").lower() != "paired":
        continue
    udid = hw.get("udid") or ""
    if not udid:
        continue
    name = props.get("name") or "(unknown)"
    tunnel = (conn.get("tunnelState") or "").lower()
    rank = 1 if tunnel == "connected" else 0
    watches.append((rank, udid, name))

if not watches:
    sys.exit(1)

watches.sort(key=lambda w: (-w[0], w[2]))
_, udid, name = watches[0]
sys.stdout.write(udid)
sys.stderr.write(f"==> Found paired Apple Watch: {name} ({udid})\n")
PY
}

WATCH_UDID_RESOLVED="$(discover_watch_udid || true)"

if [[ -z "$WATCH_UDID_RESOLVED" ]]; then
    {
        echo "error: no paired Apple Watch detected via xcrun devicectl."
        echo ""
        echo "Make sure the watch is paired with this Mac in Xcode's Devices and"
        echo "Simulators window. If discovery still fails, pass the UDID directly:"
        echo ""
        echo "  WATCH_UDID=00008301-XXXXXXXXXXXX $(basename "$0")"
        echo ""
        echo "Find your watch UDID in Xcode under Window > Devices and Simulators,"
        echo "or via 'xcrun devicectl list devices' once the watch is reachable."
    } >&2
    exit 1
fi

if [[ "$PRINT_ONLY" == "1" ]]; then
    printf '%s\n' "$WATCH_UDID_RESOLVED"
    exit 0
fi

if [[ "$DRY_RUN" == "1" ]]; then
    echo "==> [dry-run] would register watch UDID: $WATCH_UDID_RESOLVED"
    echo "==> [dry-run] xcodebuild -project $PROJECT_PATH \\"
    echo "                  -scheme $WATCH_SCHEME \\"
    echo "                  -configuration $XCODE_CONFIG \\"
    echo "                  -destination \"platform=watchOS,id=$WATCH_UDID_RESOLVED\" \\"
    echo "                  -allowProvisioningUpdates \\"
    echo "                  -allowProvisioningDeviceRegistration \\"
    echo "                  build"
    printf '%s\n' "$WATCH_UDID_RESOLVED"
    exit 0
fi

if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "error: $PROJECT_PATH does not exist — run 'make xcgen' first" >&2
    exit 1
fi

echo "==> Registering Apple Watch $WATCH_UDID_RESOLVED with the developer portal..."
echo "    (xcodebuild output streams below — first run on a new watch can take a while)"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$WATCH_SCHEME" \
    -configuration "$XCODE_CONFIG" \
    -destination "platform=watchOS,id=$WATCH_UDID_RESOLVED" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    build

echo "==> Registered. The watch UDID should now appear in the LitterWatch provisioning profile."
printf '%s\n' "$WATCH_UDID_RESOLVED"
