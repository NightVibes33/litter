#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=release-common.sh
source "$SCRIPT_DIR/release-common.sh"

SCHEME="${SCHEME:-Litter}"
CONFIGURATION="${CONFIGURATION:-Release}"
PROJECT_DIR="${PROJECT_DIR:-$IOS_DIR}"
PROJECT_PATH="${PROJECT_PATH:-$PROJECT_DIR/Litter.xcodeproj}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.sigkitten.litter.39A8Q3T3TR}"
APP_STORE_APP_ID="${APP_STORE_APP_ID:-}"
TEAM_ID="${TEAM_ID:-}"
PROVISIONING_PROFILE_SPECIFIER="${PROVISIONING_PROFILE_SPECIFIER:-Litter App Store}"
APP_PROVISIONING_PROFILE_SPECIFIER="${APP_PROVISIONING_PROFILE_SPECIFIER:-$PROVISIONING_PROFILE_SPECIFIER}"
LIVE_ACTIVITY_BUNDLE_ID="${LIVE_ACTIVITY_BUNDLE_ID:-com.sigkitten.litter.39A8Q3T3TR.liveactivity}"
LIVE_ACTIVITY_PROVISIONING_PROFILE_SPECIFIER="${LIVE_ACTIVITY_PROVISIONING_PROFILE_SPECIFIER:-}"
LIVEPROCESS_BUNDLE_ID="${LIVEPROCESS_BUNDLE_ID:-com.sigkitten.litter.39A8Q3T3TR.liveprocess}"
LIVEPROCESS_PROVISIONING_PROFILE_SPECIFIER="${LIVEPROCESS_PROVISIONING_PROFILE_SPECIFIER:-}"
WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-com.sigkitten.litter.39A8Q3T3TR.watchkitapp}"
WATCH_PROVISIONING_PROFILE_SPECIFIER="${WATCH_PROVISIONING_PROFILE_SPECIFIER:-}"
WATCH_COMP_BUNDLE_ID="${WATCH_COMP_BUNDLE_ID:-com.sigkitten.litter.39A8Q3T3TR.watchkitapp.complications}"
WATCH_COMP_PROVISIONING_PROFILE_SPECIFIER="${WATCH_COMP_PROVISIONING_PROFILE_SPECIFIER:-}"
APP_CODE_SIGN_IDENTITY="${APP_CODE_SIGN_IDENTITY:-Apple Distribution}"
LIVE_ACTIVITY_CODE_SIGN_IDENTITY="${LIVE_ACTIVITY_CODE_SIGN_IDENTITY:-Apple Distribution}"
LIVEPROCESS_CODE_SIGN_IDENTITY="${LIVEPROCESS_CODE_SIGN_IDENTITY:-Apple Distribution}"
WATCH_CODE_SIGN_IDENTITY="${WATCH_CODE_SIGN_IDENTITY:-Apple Distribution}"
WATCH_COMP_CODE_SIGN_IDENTITY="${WATCH_COMP_CODE_SIGN_IDENTITY:-Apple Distribution}"
AUTOMATIC_ARCHIVE_CODE_SIGN_IDENTITY="${AUTOMATIC_ARCHIVE_CODE_SIGN_IDENTITY:-Apple Development}"
EXPORT_SIGNING_STYLE="${EXPORT_SIGNING_STYLE:-automatic}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
ASSIGN_BETA_GROUP="${ASSIGN_BETA_GROUP:-1}"
INTERNAL_BETA_GROUP_NAME="${INTERNAL_BETA_GROUP_NAME:-Internal Testers}"
EXTERNAL_BETA_GROUP_NAME="${EXTERNAL_BETA_GROUP_NAME:-Beta Testers}"
LEGACY_BETA_GROUP_NAME="${BETA_GROUP_NAME:-}"
if [[ -n "${BETA_GROUP_NAMES:-}" ]]; then
    BETA_GROUP_NAMES="${BETA_GROUP_NAMES}"
elif [[ -n "$LEGACY_BETA_GROUP_NAME" ]]; then
    BETA_GROUP_NAMES="$LEGACY_BETA_GROUP_NAME"
else
    BETA_GROUP_NAMES="$INTERNAL_BETA_GROUP_NAME,$EXTERNAL_BETA_GROUP_NAME"
fi
SUBMIT_BETA_REVIEW="${SUBMIT_BETA_REVIEW:-1}"
WAIT_FOR_PROCESSING="${WAIT_FOR_PROCESSING:-1}"
BUILD_POLL_TIMEOUT_SECONDS="${BUILD_POLL_TIMEOUT_SECONDS:-900}"
BUILD_POLL_INTERVAL_SECONDS="${BUILD_POLL_INTERVAL_SECONDS:-15}"
WHAT_TO_TEST="${WHAT_TO_TEST:-}"
WHAT_TO_TEST_LOCALE="${WHAT_TO_TEST_LOCALE:-en-US}"
WHAT_TO_TEST_FILE="${WHAT_TO_TEST_FILE:-$TESTFLIGHT_WHATS_NEW_FILE}"
AUTO_GENERATE_WHAT_TO_TEST="${AUTO_GENERATE_WHAT_TO_TEST:-1}"
WHAT_TO_TEST_MAX_COMMITS="${WHAT_TO_TEST_MAX_COMMITS:-8}"
AUTO_ASSIGN_ENCRYPTION_DECLARATION="${AUTO_ASSIGN_ENCRYPTION_DECLARATION:-1}"
BETA_APP_DESCRIPTION_LOCALE="${BETA_APP_DESCRIPTION_LOCALE:-$WHAT_TO_TEST_LOCALE}"
BETA_APP_DESCRIPTION="${BETA_APP_DESCRIPTION:-Alley Cãt lets testers verify the iOS app experience, settings, and TestFlight distribution before public release.}"
BETA_FEEDBACK_EMAIL="${BETA_FEEDBACK_EMAIL:-NightVibes33@users.noreply.github.com}"
BETA_MARKETING_URL="${BETA_MARKETING_URL:-}"
BETA_PRIVACY_POLICY_URL="${BETA_PRIVACY_POLICY_URL:-}"
REVIEW_CONTACT_EMAIL="${REVIEW_CONTACT_EMAIL:-$BETA_FEEDBACK_EMAIL}"
REVIEW_CONTACT_FIRST_NAME="${REVIEW_CONTACT_FIRST_NAME:-Night}"
REVIEW_CONTACT_LAST_NAME="${REVIEW_CONTACT_LAST_NAME:-Vibes}"
REVIEW_CONTACT_PHONE="${REVIEW_CONTACT_PHONE:-5558675309}"
REVIEW_NOTES="${REVIEW_NOTES:-No sign-in is required. Please test the Alley Cãt app experience, settings, and TestFlight distribution behavior.}"
TESTFLIGHT_SKIP_BUILD="${TESTFLIGHT_SKIP_BUILD:-0}"
TESTFLIGHT_SKIP_UPLOAD="${TESTFLIGHT_SKIP_UPLOAD:-0}"
TESTFLIGHT_AUTO_BUMP_VERSION="${TESTFLIGHT_AUTO_BUMP_VERSION:-1}"
PROJECT_VERSION_BUMP_REQUIRED="${PROJECT_VERSION_BUMP_REQUIRED:-0}"
PROJECT_VERSION_BUMP_TARGET="${PROJECT_VERSION_BUMP_TARGET:-}"
INCLUDE_LIVEPROCESS="${INCLUDE_LIVEPROCESS:-1}"
LITTER_TESTFLIGHT_FAST="${LITTER_TESTFLIGHT_FAST:-0}"
REPAIR_EXPORTED_IPA_NATIVE_MODULES="${REPAIR_EXPORTED_IPA_NATIVE_MODULES:-0}"

if [[ "$INCLUDE_LIVEPROCESS" != "0" && "$INCLUDE_LIVEPROCESS" != "1" ]]; then
    echo "INCLUDE_LIVEPROCESS must be 0 or 1." >&2
    exit 1
fi

AUTH_KEY_PATH="${AUTH_KEY_PATH:-${ASC_PRIVATE_KEY_PATH:-}}"
AUTH_KEY_ID="${AUTH_KEY_ID:-${ASC_KEY_ID:-}}"
AUTH_ISSUER_ID="${AUTH_ISSUER_ID:-${ASC_ISSUER_ID:-}}"

BUILD_DIR="${BUILD_DIR:-$IOS_DIR/build/testflight}"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"
IPA_PATH="$BUILD_DIR/$SCHEME.ipa"
BUILD_METADATA_PATH="${BUILD_METADATA_PATH:-$BUILD_DIR/testflight-build.env}"

require_cmd asc
require_cmd jq
require_cmd curl
require_cmd openssl
require_cmd xcodebuild
require_cmd xcodegen

if [[ -x "$SCRIPT_DIR/sanitize-ios-frameworks.sh" ]]; then
    "$SCRIPT_DIR/sanitize-ios-frameworks.sh"
fi

mkdir -p "$BUILD_DIR"

if [[ "$TESTFLIGHT_SKIP_BUILD" == "1" && -f "$BUILD_METADATA_PATH" ]]; then
    # shellcheck disable=SC1090
    source "$BUILD_METADATA_PATH"
elif [[ "$TESTFLIGHT_SKIP_BUILD" == "1" ]]; then
    echo "Missing build metadata at $BUILD_METADATA_PATH for TESTFLIGHT_SKIP_BUILD=1." >&2
    exit 1
fi

resolve_requested_testflight_version() {
    local project_version resolved_version next_version

    if [[ -n "$MARKETING_VERSION" ]]; then
        ensure_semver "$MARKETING_VERSION"
        PROJECT_VERSION_BUMP_REQUIRED="${PROJECT_VERSION_BUMP_REQUIRED:-0}"
        PROJECT_VERSION_BUMP_TARGET="${PROJECT_VERSION_BUMP_TARGET:-}"
        echo "$MARKETING_VERSION"
        return 0
    fi

    project_version="$(read_project_marketing_version)"
    ensure_semver "$project_version"
    resolved_version="$project_version"
    PROJECT_VERSION_BUMP_REQUIRED=0
    PROJECT_VERSION_BUMP_TARGET=""

    if [[ "$TESTFLIGHT_AUTO_BUMP_VERSION" == "1" ]] && testflight_version_requires_bump "$APP_STORE_APP_ID" "$project_version"; then
        next_version="$(next_patch_version "$project_version")"
        echo "==> Repo version $project_version is already in App Store distribution; using next TestFlight version $next_version" >&2
        resolved_version="$next_version"
        PROJECT_VERSION_BUMP_REQUIRED=1
        PROJECT_VERSION_BUMP_TARGET="$next_version"
    fi

    echo "$resolved_version"
}

persist_build_metadata() {
    cat >"$BUILD_METADATA_PATH" <<EOF
BUILD_NUMBER=$(printf '%q' "$BUILD_NUMBER")
APP_STORE_APP_ID=$(printf '%q' "$APP_STORE_APP_ID")
TEAM_ID=$(printf '%q' "$TEAM_ID")
PROVISIONING_PROFILE_SPECIFIER=$(printf '%q' "$PROVISIONING_PROFILE_SPECIFIER")
APP_PROVISIONING_PROFILE_SPECIFIER=$(printf '%q' "$APP_PROVISIONING_PROFILE_SPECIFIER")
LIVE_ACTIVITY_BUNDLE_ID=$(printf '%q' "$LIVE_ACTIVITY_BUNDLE_ID")
LIVE_ACTIVITY_PROVISIONING_PROFILE_SPECIFIER=$(printf '%q' "$LIVE_ACTIVITY_PROVISIONING_PROFILE_SPECIFIER")
LIVEPROCESS_BUNDLE_ID=$(printf '%q' "$LIVEPROCESS_BUNDLE_ID")
LIVEPROCESS_PROVISIONING_PROFILE_SPECIFIER=$(printf '%q' "$LIVEPROCESS_PROVISIONING_PROFILE_SPECIFIER")
INCLUDE_LIVEPROCESS=$(printf '%q' "$INCLUDE_LIVEPROCESS")
LITTER_TESTFLIGHT_FAST=$(printf '%q' "$LITTER_TESTFLIGHT_FAST")
WATCH_BUNDLE_ID=$(printf '%q' "$WATCH_BUNDLE_ID")
WATCH_PROVISIONING_PROFILE_SPECIFIER=$(printf '%q' "$WATCH_PROVISIONING_PROFILE_SPECIFIER")
WATCH_COMP_BUNDLE_ID=$(printf '%q' "$WATCH_COMP_BUNDLE_ID")
WATCH_COMP_PROVISIONING_PROFILE_SPECIFIER=$(printf '%q' "$WATCH_COMP_PROVISIONING_PROFILE_SPECIFIER")
MARKETING_VERSION=$(printf '%q' "$MARKETING_VERSION")
WHAT_TO_TEST_LOCALE=$(printf '%q' "$WHAT_TO_TEST_LOCALE")
PROJECT_VERSION_BUMP_REQUIRED=$(printf '%q' "$PROJECT_VERSION_BUMP_REQUIRED")
PROJECT_VERSION_BUMP_TARGET=$(printf '%q' "$PROJECT_VERSION_BUMP_TARGET")
EOF
}

APP_STORE_APP_ID="$(resolve_app_store_app_id "$APP_STORE_APP_ID" "$APP_BUNDLE_ID")"
TEAM_ID="$(resolve_team_id "$TEAM_ID" "$PROJECT_PATH" "$SCHEME" "$CONFIGURATION" "$EXPORT_SIGNING_STYLE" "$APP_PROVISIONING_PROFILE_SPECIFIER")"

if [[ "$EXPORT_SIGNING_STYLE" != "automatic" && "$EXPORT_SIGNING_STYLE" != "manual" ]]; then
    echo "Unsupported EXPORT_SIGNING_STYLE: $EXPORT_SIGNING_STYLE" >&2
    echo "Expected 'automatic' or 'manual'." >&2
    exit 1
fi

if [[ "$EXPORT_SIGNING_STYLE" == "manual" && -z "$APP_PROVISIONING_PROFILE_SPECIFIER" ]]; then
    echo "Manual export signing requires APP_PROVISIONING_PROFILE_SPECIFIER." >&2
    exit 1
fi

if [[ "$EXPORT_SIGNING_STYLE" == "manual" && -z "$LIVE_ACTIVITY_PROVISIONING_PROFILE_SPECIFIER" ]]; then
    echo "Manual export signing requires LIVE_ACTIVITY_PROVISIONING_PROFILE_SPECIFIER." >&2
    exit 1
fi

if [[ "$EXPORT_SIGNING_STYLE" == "manual" && "$INCLUDE_LIVEPROCESS" == "1" && -z "$LIVEPROCESS_PROVISIONING_PROFILE_SPECIFIER" ]]; then
    echo "Manual export signing requires LIVEPROCESS_PROVISIONING_PROFILE_SPECIFIER." >&2
    exit 1
fi

if [[ "$EXPORT_SIGNING_STYLE" == "manual" && -z "$WATCH_PROVISIONING_PROFILE_SPECIFIER" ]]; then
    echo "Manual export signing requires WATCH_PROVISIONING_PROFILE_SPECIFIER." >&2
    exit 1
fi

if [[ "$EXPORT_SIGNING_STYLE" == "manual" && -z "$WATCH_COMP_PROVISIONING_PROFILE_SPECIFIER" ]]; then
    echo "Manual export signing requires WATCH_COMP_PROVISIONING_PROFILE_SPECIFIER." >&2
    exit 1
fi

MARKETING_VERSION="$(resolve_requested_testflight_version)"

if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$(resolve_next_build_number "$APP_STORE_APP_ID")"
fi

if [[ -z "$WHAT_TO_TEST" && -f "$WHAT_TO_TEST_FILE" ]]; then
    WHAT_TO_TEST="$(cat "$WHAT_TO_TEST_FILE")"
fi

if [[ -z "$WHAT_TO_TEST" && "$AUTO_GENERATE_WHAT_TO_TEST" == "1" ]]; then
    WHAT_TO_TEST="$(
        git -C "$ROOT_DIR" log --no-merges -n "$WHAT_TO_TEST_MAX_COMMITS" --pretty='- %s' |
            sed '/^[[:space:]]*$/d'
    )"
fi

if [[ -z "$WHAT_TO_TEST" ]]; then
    echo "Missing TestFlight changelog (What to Test)." >&2
    echo "Set WHAT_TO_TEST, or populate $WHAT_TO_TEST_FILE." >&2
    exit 1
fi

persist_build_metadata

auth_args=()
if [[ -n "$AUTH_KEY_PATH" && -n "$AUTH_KEY_ID" && -n "$AUTH_ISSUER_ID" ]]; then
    auth_args=(
        -authenticationKeyPath "$AUTH_KEY_PATH"
        -authenticationKeyID "$AUTH_KEY_ID"
        -authenticationKeyIssuerID "$AUTH_ISSUER_ID"
    )
fi

if [[ "$TESTFLIGHT_SKIP_BUILD" != "1" ]]; then
    if [[ "$LITTER_TESTFLIGHT_FAST" == "1" ]]; then
        echo "==> Applying fast TestFlight project mode"
        python3 "$ROOT_DIR/tools/scripts/patch-ios-testflight-fast-project.py"
    fi

    echo "==> Regenerating Xcode project"
    "$PROJECT_DIR/scripts/regenerate-project.sh"

    echo "==> Archiving $SCHEME ($MARKETING_VERSION/$BUILD_NUMBER)"
    archive_cmd=(
        xcodebuild
        -project "$PROJECT_PATH"
        -scheme "$SCHEME"
        -configuration "$CONFIGURATION"
        -destination "generic/platform=iOS"
        -archivePath "$ARCHIVE_PATH"
        clean archive
        MARKETING_VERSION="$MARKETING_VERSION"
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
    )

    if [[ -n "$TEAM_ID" ]]; then
        archive_cmd+=(DEVELOPMENT_TEAM="$TEAM_ID")
    fi

    if [[ "$EXPORT_SIGNING_STYLE" == "manual" ]]; then
        archive_cmd+=(
            APP_CODE_SIGN_STYLE=Manual
            LIVE_ACTIVITY_CODE_SIGN_STYLE=Manual
            WATCH_CODE_SIGN_STYLE=Manual
            WATCH_COMP_CODE_SIGN_STYLE=Manual
            APP_PROVISIONING_PROFILE_SPECIFIER="$APP_PROVISIONING_PROFILE_SPECIFIER"
            LIVE_ACTIVITY_PROVISIONING_PROFILE_SPECIFIER="$LIVE_ACTIVITY_PROVISIONING_PROFILE_SPECIFIER"
            WATCH_PROVISIONING_PROFILE_SPECIFIER="$WATCH_PROVISIONING_PROFILE_SPECIFIER"
            WATCH_COMP_PROVISIONING_PROFILE_SPECIFIER="$WATCH_COMP_PROVISIONING_PROFILE_SPECIFIER"
            APP_CODE_SIGN_IDENTITY="$APP_CODE_SIGN_IDENTITY"
            LIVE_ACTIVITY_CODE_SIGN_IDENTITY="$LIVE_ACTIVITY_CODE_SIGN_IDENTITY"
            WATCH_CODE_SIGN_IDENTITY="$WATCH_CODE_SIGN_IDENTITY"
            WATCH_COMP_CODE_SIGN_IDENTITY="$WATCH_COMP_CODE_SIGN_IDENTITY"
        )
        if [[ "$INCLUDE_LIVEPROCESS" == "1" ]]; then
            archive_cmd+=(
                LIVEPROCESS_CODE_SIGN_STYLE=Manual
                LIVEPROCESS_PROVISIONING_PROFILE_SPECIFIER="$LIVEPROCESS_PROVISIONING_PROFILE_SPECIFIER"
                LIVEPROCESS_CODE_SIGN_IDENTITY="$LIVEPROCESS_CODE_SIGN_IDENTITY"
            )
        fi
    else
        archive_cmd+=(
            APP_CODE_SIGN_STYLE=Automatic
            LIVE_ACTIVITY_CODE_SIGN_STYLE=Automatic
            WATCH_CODE_SIGN_STYLE=Automatic
            WATCH_COMP_CODE_SIGN_STYLE=Automatic
            APP_CODE_SIGN_IDENTITY="$AUTOMATIC_ARCHIVE_CODE_SIGN_IDENTITY"
            LIVE_ACTIVITY_CODE_SIGN_IDENTITY="$AUTOMATIC_ARCHIVE_CODE_SIGN_IDENTITY"
            WATCH_CODE_SIGN_IDENTITY="$AUTOMATIC_ARCHIVE_CODE_SIGN_IDENTITY"
            WATCH_COMP_CODE_SIGN_IDENTITY="$AUTOMATIC_ARCHIVE_CODE_SIGN_IDENTITY"
            -allowProvisioningUpdates
        )
        if [[ "$INCLUDE_LIVEPROCESS" == "1" ]]; then
            archive_cmd+=(
                LIVEPROCESS_CODE_SIGN_STYLE=Automatic
                LIVEPROCESS_CODE_SIGN_IDENTITY="$AUTOMATIC_ARCHIVE_CODE_SIGN_IDENTITY"
            )
        fi
    fi

    if [[ "$EXPORT_SIGNING_STYLE" == "automatic" && "${#auth_args[@]}" -gt 0 ]]; then
        archive_cmd+=("${auth_args[@]}")
    fi

    "${archive_cmd[@]}"

    cat >"$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>app-store-connect</string>
    <key>signingStyle</key>
    <string>${EXPORT_SIGNING_STYLE}</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF

    if [[ -n "$TEAM_ID" ]]; then
        /usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$EXPORT_OPTIONS_PLIST"
    fi
    if [[ "$EXPORT_SIGNING_STYLE" == "manual" ]]; then
        /usr/libexec/PlistBuddy -c "Add :provisioningProfiles dict" "$EXPORT_OPTIONS_PLIST"
        /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$APP_BUNDLE_ID string $APP_PROVISIONING_PROFILE_SPECIFIER" "$EXPORT_OPTIONS_PLIST"
        /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$LIVE_ACTIVITY_BUNDLE_ID string $LIVE_ACTIVITY_PROVISIONING_PROFILE_SPECIFIER" "$EXPORT_OPTIONS_PLIST"
        if [[ "$INCLUDE_LIVEPROCESS" == "1" ]]; then
            /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$LIVEPROCESS_BUNDLE_ID string $LIVEPROCESS_PROVISIONING_PROFILE_SPECIFIER" "$EXPORT_OPTIONS_PLIST"
        fi
        /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$WATCH_BUNDLE_ID string $WATCH_PROVISIONING_PROFILE_SPECIFIER" "$EXPORT_OPTIONS_PLIST"
        /usr/libexec/PlistBuddy -c "Add :provisioningProfiles:$WATCH_COMP_BUNDLE_ID string $WATCH_COMP_PROVISIONING_PROFILE_SPECIFIER" "$EXPORT_OPTIONS_PLIST"
    fi

    echo "==> Exporting IPA (signing: $EXPORT_SIGNING_STYLE)"
    export_cmd=(
        xcodebuild
        -exportArchive
        -archivePath "$ARCHIVE_PATH"
        -exportPath "$BUILD_DIR"
        -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
    )

    if [[ "$EXPORT_SIGNING_STYLE" == "automatic" ]]; then
        export_cmd+=(-allowProvisioningUpdates)
    fi

    if [[ "$EXPORT_SIGNING_STYLE" == "automatic" && "${#auth_args[@]}" -gt 0 ]]; then
        export_cmd+=("${auth_args[@]}")
    fi

    "${export_cmd[@]}"

    exported_ipa="$(find "$BUILD_DIR" -maxdepth 1 -name "*.ipa" | head -n 1)"
    if [[ -z "$exported_ipa" ]]; then
        echo "No IPA produced in $BUILD_DIR" >&2
        exit 1
    fi
    if [[ "$exported_ipa" != "$IPA_PATH" ]]; then
        cp "$exported_ipa" "$IPA_PATH"
    fi
fi

if [[ ! -f "$IPA_PATH" ]]; then
    echo "Expected IPA at $IPA_PATH" >&2
    exit 1
fi

repair_exported_ipa_native_module_signatures() {
    local ipa_path="$1"
    local work_dir payload_app entitlements_plist signed_count hidden_count changed_count repaired_ipa sign_identity native_list

    if [[ "$REPAIR_EXPORTED_IPA_NATIVE_MODULES" != "1" ]]; then
        echo "==> Skipping exported IPA native module repair (set REPAIR_EXPORTED_IPA_NATIVE_MODULES=1 to enable)" >&2
        return 0
    fi

    echo "==> Repairing exported IPA native module packaging"
    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/litter-ipa-repair.XXXXXX")"
    trap 'rm -rf "$work_dir"' RETURN

    unzip -q "$ipa_path" -d "$work_dir"
    payload_app="$(find "$work_dir/Payload" -maxdepth 1 -type d -name "*.app" | head -n 1)"
    if [[ -z "$payload_app" ]]; then
        echo "Unable to find Payload/*.app inside $ipa_path" >&2
        exit 1
    fi

    native_list="$work_dir/native-modules.txt"
    find "$payload_app" -type f \( -name "*.so" -o -name "*.dylib" \) -print >"$native_list"
    echo "Found $(wc -l <"$native_list" | tr -d ' ') exported IPA native module candidate(s)"

    sign_identity="${CODESIGN_REPAIR_IDENTITY:-${APP_CODE_SIGN_IDENTITY:-Apple Distribution}}"
    signed_count=0
    hidden_count=0
    while IFS= read -r native_module; do
        [[ -n "$native_module" ]] || continue
        if /usr/bin/file "$native_module" 2>/dev/null | /usr/bin/grep -q 'Mach-O'; then
            /usr/bin/codesign --force --sign "$sign_identity" --timestamp=none "$native_module"
            signed_count=$((signed_count + 1))
            echo "Signed exported IPA native module: ${native_module#$payload_app/}"
        else
            mv "$native_module" "${native_module}.litter-elf"
            hidden_count=$((hidden_count + 1))
            echo "Hid non-Mach-O native module from Apple code signing scan: ${native_module#$payload_app/}"
        fi
    done <"$native_list"

    changed_count=$((signed_count + hidden_count))

    echo "Refreshing exported IPA root app signature seal"
    entitlements_plist="$work_dir/app-entitlements.plist"
    if /usr/bin/codesign -d --entitlements :- "$payload_app" >"$entitlements_plist" 2>/dev/null && [[ -s "$entitlements_plist" ]]; then
        /usr/bin/codesign --force --sign "$sign_identity" --timestamp=none --entitlements "$entitlements_plist" --generate-entitlement-der "$payload_app"
    else
        /usr/bin/codesign --force --sign "$sign_identity" --timestamp=none --generate-entitlement-der "$payload_app"
    fi

    repaired_ipa="$work_dir/repaired.ipa"
    (cd "$work_dir" && /usr/bin/zip -qry "$repaired_ipa" Payload)
    cp "$repaired_ipa" "$ipa_path"
    echo "Repacked exported IPA after refreshing the root app seal, signing $signed_count Mach-O module(s), and hiding $hidden_count non-Mach-O module(s)"
}

repair_exported_ipa_native_module_signatures "$IPA_PATH"

verify_exported_ipa_contains_bundled_ish_fs() {
    local ipa_path="$1"
    local work_dir payload_app

    echo "==> Verifying exported IPA contains bundled iSH filesystem"
    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/litter-ipa-fs-check.XXXXXX")"
    trap 'rm -rf "$work_dir"' RETURN

    unzip -q "$ipa_path" -d "$work_dir"
    payload_app="$(find "$work_dir/Payload" -maxdepth 1 -type d -name "*.app" | head -n 1)"
    if [[ -z "$payload_app" ]]; then
        echo "Unable to find Payload/*.app inside $ipa_path" >&2
        exit 1
    fi

    if [[ ! -s "$payload_app/fs.tar.gz" ]]; then
        echo "Exported IPA is missing fs.tar.gz in the app bundle." >&2
        echo "Without it, local iSH shell bootstrap fails with: bundled iSH filesystem is missing." >&2
        exit 1
    fi

    if [[ ! -s "$payload_app/fs.version" ]]; then
        echo "Exported IPA is missing fs.version in the app bundle." >&2
        exit 1
    fi
}

verify_exported_ipa_signature() {
    local ipa_path="$1"
    local work_dir payload_app signature_info strict_log relaxed_log diagnostics_log

    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/litter-ipa-verify.XXXXXX")"
    trap 'rm -rf "$work_dir"' RETURN

    unzip -q "$ipa_path" -d "$work_dir"
    payload_app="$(find "$work_dir/Payload" -maxdepth 1 -type d -name "*.app" | head -n 1)"
    if [[ -z "$payload_app" ]]; then
        echo "Unable to find Payload/*.app inside $ipa_path" >&2
        exit 1
    fi

    echo "==> Verifying exported IPA signature"
    signature_info="$work_dir/root-signature.txt"
    /usr/bin/codesign -dv --verbose=4 "$payload_app" >"$signature_info" 2>&1 || true
    cat "$signature_info"
    if ! grep -Eq "Authority=(Apple|iPhone) Distribution" "$signature_info"; then
        echo "Exported IPA is not signed by an Apple/iPhone distribution authority." >&2
        exit 1
    fi

    strict_log="$work_dir/codesign-strict.log"
    if /usr/bin/codesign --verify --deep --strict --verbose=6 "$payload_app" >"$strict_log" 2>&1; then
        cat "$strict_log"
        return 0
    fi

    echo "Strict exported IPA signature verification failed:" >&2
    cat "$strict_log" >&2
    echo "==> Checking relaxed exported IPA signature" >&2
    relaxed_log="$work_dir/codesign-relaxed.log"
    if /usr/bin/codesign --verify --deep --verbose=6 "$payload_app" >"$relaxed_log" 2>&1; then
        cat "$relaxed_log" >&2
        echo "Strict verification failed, but relaxed distribution-signature verification passed." >&2
        echo "Continuing to App Store Connect upload for authoritative TestFlight validation." >&2
        return 0
    fi

    echo "Relaxed exported IPA signature verification also failed:" >&2
    cat "$relaxed_log" >&2
    echo "==> Embedded code signature diagnostics" >&2
    diagnostics_log="$work_dir/embedded-signature-diagnostics.log"
    {
        {
            find "$payload_app" -type d \( -name "*.app" -o -name "*.appex" -o -name "*.framework" \) -print
            find "$payload_app" -type f \( -name "*.dylib" -o -name "*.so" \) -print
        } | sort -u | while IFS= read -r signed_item; do
            echo "--- $signed_item"
            /usr/bin/codesign --verify --strict --verbose=6 "$signed_item" || true
        done
    } >"$diagnostics_log" 2>&1
    cat "$diagnostics_log" >&2

    if [[ "${ALLOW_XCODE_EXPORTED_SEAL_WARNING:-0}" == "1" ]] &&
        grep -q "a sealed resource is missing or invalid" "$strict_log" &&
        grep -q "a sealed resource is missing or invalid" "$relaxed_log" &&
        ! grep -Eq "code object is not signed|not signed at all|CSSMERR|invalid signature|bundle format unrecognized|main executable failed strict validation|code has no resources|unsealed contents present" "$strict_log" "$relaxed_log" "$diagnostics_log"; then
        echo "Xcode exported a distribution-signed IPA with a generic local sealed-resource warning, but all embedded signed code verified." >&2
        echo "ALLOW_XCODE_EXPORTED_SEAL_WARNING=1 is set, so continuing to App Store Connect upload for authoritative TestFlight validation." >&2
        return 0
    fi

    exit 1
}

verify_testflight_fast_ipa_is_app_store_safe() {
    local ipa_path="$1"
    local work_dir payload_app offenders_log selector_log

    if [[ "$LITTER_TESTFLIGHT_FAST" != "1" ]]; then
        return 0
    fi


    echo "==> Checking fast TestFlight IPA for app-store-unsafe embedded tooling"
    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/litter-ipa-appstore-safe.XXXXXX")"
    unzip -q "$ipa_path" -d "$work_dir"
    payload_app="$(find "$work_dir/Payload" -maxdepth 1 -type d -name "*.app" | head -n 1)"
    if [[ -z "$payload_app" ]]; then
        echo "Unable to find app bundle in exported IPA while checking TestFlight fast safety." >&2
        exit 1
    fi

    offenders_log="$work_dir/app-store-unsafe-frameworks.txt"
    find "$payload_app" -path '*/Frameworks/*.framework' -maxdepth 4 -print |
        grep -E '/(AltSign-Dynamic|SideStore|AltStoreCore|Roxas|Minimuxer|RustBridge)\.framework$' >"$offenders_log" || true
    if [[ -s "$offenders_log" ]]; then
        echo "Fast TestFlight IPA still embeds App-Store-unsafe sideload/provisioning frameworks:" >&2
        cat "$offenders_log" >&2
        exit 1
    fi

    selector_log="$work_dir/app-store-unsafe-selectors.txt"
    grep -R -a -E 'installApplicationWithArchiveObject|installApplicationWithPayloadPath|installApplicationAtPackagePath|installApplicationAtBundlePath|misagent_|com\.apple\.misagent|MobileInstallation|LSApplicationWorkspace|FrontBoardServices|BackBoardServices|SpringBoardServices|PrivateFrameworks' "$payload_app" >"$selector_log" 2>/dev/null || true
    if [[ -s "$selector_log" ]]; then
        echo "Fast TestFlight IPA contains strings that commonly trigger ITMS-90338 non-public API validation:" >&2
        head -n 80 "$selector_log" >&2
        exit 1
    fi
}

verify_exported_ipa_contains_bundled_ish_fs "$IPA_PATH"
verify_exported_ipa_signature "$IPA_PATH"
verify_testflight_fast_ipa_is_app_store_safe "$IPA_PATH"

if [[ "$TESTFLIGHT_SKIP_UPLOAD" == "1" ]]; then
    echo "==> TestFlight build prepared"
    echo "    IPA:         $IPA_PATH"
    echo "    Version:     $MARKETING_VERSION"
    echo "    Build:       $BUILD_NUMBER"
    exit 0
fi

echo "==> Uploading IPA to App Store Connect (app: $APP_STORE_APP_ID)"
upload_cmd=(
    asc builds upload
    --app "$APP_STORE_APP_ID"
    --ipa "$IPA_PATH"
    --version "$MARKETING_VERSION"
    --build-number "$BUILD_NUMBER"
    --output json
)
if [[ "$WAIT_FOR_PROCESSING" == "1" ]]; then
    upload_cmd+=(--wait)
fi

if ! upload_json="$("${upload_cmd[@]}")"; then
    echo "TestFlight upload failed for version $MARKETING_VERSION / build $BUILD_NUMBER." >&2
    exit 1
fi
echo "$upload_json" >"$BUILD_DIR/upload_result.json"

build_id="$(
    echo "$upload_json" |
        jq -r '.data.id // .data[0].id // empty'
)"
if [[ -z "$build_id" ]]; then
    build_id="$(find_build_id "$APP_STORE_APP_ID" "$MARKETING_VERSION" "$BUILD_NUMBER" 20)"
fi

if [[ -z "$build_id" && "$ASSIGN_BETA_GROUP" == "1" ]]; then
    deadline="$(( $(date +%s) + BUILD_POLL_TIMEOUT_SECONDS ))"
    while [[ -z "$build_id" && "$(date +%s)" -lt "$deadline" ]]; do
        sleep "$BUILD_POLL_INTERVAL_SECONDS"
        build_id="$(find_build_id "$APP_STORE_APP_ID" "$MARKETING_VERSION" "$BUILD_NUMBER" 50)"
    done
fi

if [[ -n "$build_id" && "$AUTO_ASSIGN_ENCRYPTION_DECLARATION" == "1" ]]; then
    internal_state="$(
        asc builds build-beta-detail view --build-id "$build_id" --output json |
            jq -r '.data.attributes.internalBuildState // empty'
    )"
    if [[ "$internal_state" == "MISSING_EXPORT_COMPLIANCE" ]]; then
        declaration_id="$(
            asc encryption declarations list --app "$APP_STORE_APP_ID" --output json |
                jq -r '.data | sort_by(.attributes.createdDate // "") | last | .id // empty'
        )"
        if [[ -n "$declaration_id" ]]; then
            echo "==> Assigning build $build_id to encryption declaration $declaration_id"
            asc encryption declarations assign-builds \
                --id "$declaration_id" \
                --build "$build_id" \
                --output json >/dev/null || true
        fi
    fi
fi

if [[ -n "$build_id" && -n "$WHAT_TO_TEST" ]]; then
    echo "==> Ensuring What to Test notes are set for $WHAT_TO_TEST_LOCALE"
    # Try update first (works if localization already exists), fall back to create.
    if ! asc builds test-notes update \
            --build-id "$build_id" \
            --locale "$WHAT_TO_TEST_LOCALE" \
            --whats-new "$WHAT_TO_TEST" \
            --output json >/dev/null 2>&1; then
        asc builds test-notes create \
            --build-id "$build_id" \
            --locale "$WHAT_TO_TEST_LOCALE" \
            --whats-new "$WHAT_TO_TEST" \
            --output json >/dev/null
    fi
fi

app_store_connect_jwt() {
    python3 - "$AUTH_KEY_PATH" "$AUTH_KEY_ID" "$AUTH_ISSUER_ID" <<'JWT_PY'
import base64
import json
import subprocess
import sys
import time

key_path, key_id, issuer_id = sys.argv[1:4]

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
now = int(time.time())
payload = {"iss": issuer_id, "iat": now, "exp": now + 1199, "aud": "appstoreconnect-v1"}
unsigned = f"{b64url(json.dumps(header, separators=(',', ':')).encode())}.{b64url(json.dumps(payload, separators=(',', ':')).encode())}"
der = subprocess.check_output(["openssl", "dgst", "-sha256", "-sign", key_path], input=unsigned.encode())

index = 0
if der[index] != 0x30:
    raise SystemExit("unexpected ECDSA DER sequence")
index += 1

def read_length() -> int:
    global index
    first = der[index]
    index += 1
    if first < 0x80:
        return first
    count = first & 0x7F
    value = int.from_bytes(der[index:index + count], "big")
    index += count
    return value

_ = read_length()
parts = []
for _ in range(2):
    if der[index] != 0x02:
        raise SystemExit("unexpected ECDSA DER integer")
    index += 1
    length = read_length()
    part = der[index:index + length]
    index += length
    while len(part) > 32 and part[0] == 0:
        part = part[1:]
    if len(part) > 32:
        raise SystemExit("unexpected ECDSA integer length")
    parts.append(part.rjust(32, b"\0"))
print(unsigned + "." + b64url(parts[0] + parts[1]))
JWT_PY
}

ensure_beta_app_localization() {
    local app_id="$1"
    local locale="$2"
    local description="$3"
    local token list_json localization_id body_file api_root

    if [[ -z "$description" ]]; then
        return 0
    fi
    if [[ -z "$AUTH_KEY_PATH" || -z "$AUTH_KEY_ID" || -z "$AUTH_ISSUER_ID" ]]; then
        echo "Missing App Store Connect API key details for beta app localization update." >&2
        exit 1
    fi

    api_root="https://api.appstoreconnect.apple.com/v1"
    token="$(app_store_connect_jwt)"
    list_json="$(curl -fsS \
        -H "Authorization: Bearer $token" \
        -H 'Accept: application/json' \
        "$api_root/apps/$app_id/betaAppLocalizations?limit=200")"
    localization_id="$(echo "$list_json" | jq -r --arg locale "$locale" '.data[]? | select(.attributes.locale == $locale) | .id' | head -n 1)"
    body_file="$(mktemp "${TMPDIR:-/tmp}/beta-app-localization.XXXXXX.json")"

    if [[ -n "$localization_id" ]]; then
        BETA_APP_LOCALIZATION_ID="$localization_id" \
        BETA_APP_DESCRIPTION="$description" \
        BETA_FEEDBACK_EMAIL="$BETA_FEEDBACK_EMAIL" \
        BETA_MARKETING_URL="$BETA_MARKETING_URL" \
        BETA_PRIVACY_POLICY_URL="$BETA_PRIVACY_POLICY_URL" \
        python3 - <<'BODY_PY' >"$body_file"
import json
import os
attrs = {"description": os.environ["BETA_APP_DESCRIPTION"]}
for env_name, api_name in (
    ("BETA_FEEDBACK_EMAIL", "feedbackEmail"),
    ("BETA_MARKETING_URL", "marketingUrl"),
    ("BETA_PRIVACY_POLICY_URL", "privacyPolicyUrl"),
):
    value = os.environ.get(env_name, "").strip()
    if value:
        attrs[api_name] = value
print(json.dumps({"data": {"type": "betaAppLocalizations", "id": os.environ["BETA_APP_LOCALIZATION_ID"], "attributes": attrs}}, separators=(",", ":")))
BODY_PY
        echo "==> Updating TestFlight beta app description for $locale"
        curl -fsS -X PATCH \
            -H "Authorization: Bearer $token" \
            -H 'Accept: application/json' \
            -H 'Content-Type: application/json' \
            --data-binary "@$body_file" \
            "$api_root/betaAppLocalizations/$localization_id" >/dev/null
    else
        BETA_APP_ID="$app_id" \
        BETA_APP_DESCRIPTION_LOCALE="$locale" \
        BETA_APP_DESCRIPTION="$description" \
        BETA_FEEDBACK_EMAIL="$BETA_FEEDBACK_EMAIL" \
        BETA_MARKETING_URL="$BETA_MARKETING_URL" \
        BETA_PRIVACY_POLICY_URL="$BETA_PRIVACY_POLICY_URL" \
        python3 - <<'BODY_PY' >"$body_file"
import json
import os
attrs = {
    "locale": os.environ["BETA_APP_DESCRIPTION_LOCALE"],
    "description": os.environ["BETA_APP_DESCRIPTION"],
}
for env_name, api_name in (
    ("BETA_FEEDBACK_EMAIL", "feedbackEmail"),
    ("BETA_MARKETING_URL", "marketingUrl"),
    ("BETA_PRIVACY_POLICY_URL", "privacyPolicyUrl"),
):
    value = os.environ.get(env_name, "").strip()
    if value:
        attrs[api_name] = value
print(json.dumps({
    "data": {
        "type": "betaAppLocalizations",
        "attributes": attrs,
        "relationships": {"app": {"data": {"type": "apps", "id": os.environ["BETA_APP_ID"]}}},
    }
}, separators=(",", ":")))
BODY_PY
        echo "==> Creating TestFlight beta app description for $locale"
        curl -fsS -X POST \
            -H "Authorization: Bearer $token" \
            -H 'Accept: application/json' \
            -H 'Content-Type: application/json' \
            --data-binary "@$body_file" \
            "$api_root/betaAppLocalizations" >/dev/null
    fi
    rm -f "$body_file"
}

if [[ -n "$build_id" && -n "$BETA_APP_DESCRIPTION" ]]; then
    ensure_beta_app_localization "$APP_STORE_APP_ID" "$BETA_APP_DESCRIPTION_LOCALE" "$BETA_APP_DESCRIPTION"
fi

ensure_beta_review_details() {
    local app_id="$1"
    local review_id

    if [[ -z "$REVIEW_CONTACT_EMAIL" && -z "$REVIEW_CONTACT_FIRST_NAME" && -z "$REVIEW_CONTACT_LAST_NAME" && -z "$REVIEW_CONTACT_PHONE" && -z "$REVIEW_NOTES" ]]; then
        return 0
    fi

    review_id="$(
        asc testflight review get --app "$app_id" --output json |
            jq -r '.data[0].id // .data.id // empty'
    )"
    if [[ -z "$review_id" ]]; then
        echo "WARNING: Could not find TestFlight beta review details record for app $app_id." >&2
        return 1
    fi

    echo "==> Updating TestFlight beta review contact details"
    cmd=(asc testflight review update --id "$review_id" --output json)
    if [[ -n "$REVIEW_CONTACT_EMAIL" ]]; then
        cmd+=(--contact-email "$REVIEW_CONTACT_EMAIL")
    fi
    if [[ -n "$REVIEW_CONTACT_FIRST_NAME" ]]; then
        cmd+=(--contact-first-name "$REVIEW_CONTACT_FIRST_NAME")
    fi
    if [[ -n "$REVIEW_CONTACT_LAST_NAME" ]]; then
        cmd+=(--contact-last-name "$REVIEW_CONTACT_LAST_NAME")
    fi
    if [[ -n "$REVIEW_CONTACT_PHONE" ]]; then
        cmd+=(--contact-phone "$REVIEW_CONTACT_PHONE")
    fi
    if [[ -n "$REVIEW_NOTES" ]]; then
        cmd+=(--notes "$REVIEW_NOTES")
    fi
    "${cmd[@]}" >/dev/null
}

if [[ "$ASSIGN_BETA_GROUP" == "1" && -n "$build_id" ]]; then
    beta_group_ids=()
    external_group_requested=0

    IFS=',' read -r -a requested_group_names <<<"$BETA_GROUP_NAMES"
    for raw_group_name in "${requested_group_names[@]}"; do
        group_name="$(trim "$raw_group_name")"
        [[ -n "$group_name" ]] || continue

        beta_group_id="$(
            asc testflight groups list --app "$APP_STORE_APP_ID" --output json |
                jq -r --arg name "$group_name" '.data[] | select(.attributes.name == $name) | .id' |
                head -n 1
        )"

        if [[ -z "$beta_group_id" ]]; then
            create_cmd=(
                asc testflight groups create
                --app "$APP_STORE_APP_ID"
                --name "$group_name"
                --output json
            )
            if [[ "$group_name" == "$INTERNAL_BETA_GROUP_NAME" ]]; then
                create_cmd+=(--internal)
            else
                external_group_requested=1
            fi
            beta_group_id="$(
                "${create_cmd[@]}" |
                    jq -r '.data.id // empty'
            )"
        elif [[ "$group_name" != "$INTERNAL_BETA_GROUP_NAME" ]]; then
            external_group_requested=1
        fi

        if [[ -n "$beta_group_id" ]]; then
            beta_group_ids+=("$beta_group_id")
        fi
    done

    if [[ "${#beta_group_ids[@]}" -gt 0 ]]; then
        group_csv="$(IFS=,; printf '%s' "${beta_group_ids[*]}")"
        echo "==> Assigning build $build_id to beta groups: $BETA_GROUP_NAMES"
        deadline="$(( $(date +%s) + BUILD_POLL_TIMEOUT_SECONDS ))"
        assigned=0
        while [[ "$(date +%s)" -lt "$deadline" ]]; do
            if asc builds add-groups --build-id "$build_id" --group "$group_csv" --output json >/dev/null 2>&1; then
                assigned=1
                break
            fi
            sleep "$BUILD_POLL_INTERVAL_SECONDS"
        done
        if [[ "$assigned" -ne 1 ]]; then
            echo "Failed to assign build $build_id to beta groups '$BETA_GROUP_NAMES' within timeout." >&2
            exit 1
        fi

        if [[ "$SUBMIT_BETA_REVIEW" == "1" && "$external_group_requested" -eq 1 ]]; then
            ensure_beta_review_details "$APP_STORE_APP_ID" || true
            echo "==> Submitting build $build_id for Beta App Review"
            beta_review_submit_attempted=1
            beta_review_submit_succeeded=0
            submit_log="$BUILD_DIR/beta-review-submit.log"
            rm -f "$submit_log"
            for attempt in 1 2 3; do
                if asc testflight review submit --build-id "$build_id" --confirm --output json >"$submit_log" 2>&1; then
                    beta_review_submit_succeeded=1
                    break
                fi
                if [[ "$attempt" -lt 3 ]]; then
                    echo "Beta App Review submit failed on attempt $attempt; retrying..." >&2
                    sleep "$BUILD_POLL_INTERVAL_SECONDS"
                fi
            done
            if [[ "$beta_review_submit_succeeded" -ne 1 ]]; then
                echo "WARNING: Beta App Review submit failed after upload and group assignment." >&2
                echo "         App Store Connect accepted build $build_id; leaving CI green so the build is not lost." >&2
                sed 's/^/         /' "$submit_log" >&2 || true
            fi
        fi
    fi
fi

if [[ -n "$build_id" ]]; then
    echo "==> Validating TestFlight readiness"
    validate_log="$BUILD_DIR/testflight-validate.log"
    if ! asc validate testflight --app "$APP_STORE_APP_ID" --build "$build_id" --strict --output json >"$validate_log" 2>&1; then
        if [[ "${beta_review_submit_attempted:-0}" == "1" && "${beta_review_submit_succeeded:-0}" != "1" ]]; then
            echo "WARNING: strict TestFlight validation failed after Beta App Review submit failed." >&2
            echo "         Build $build_id is uploaded and assigned; ASC may need manual/retry review submission." >&2
            sed 's/^/         /' "$validate_log" >&2 || true
        else
            cat "$validate_log" >&2
            exit 1
        fi
    fi
fi

if [[ "$PROJECT_VERSION_BUMP_REQUIRED" == "1" ]]; then
    echo "==> Updating repo version to $PROJECT_VERSION_BUMP_TARGET for the next beta cycle"
    write_project_marketing_version "$PROJECT_VERSION_BUMP_TARGET"
    seed_testflight_whats_new_template "$WHAT_TO_TEST_FILE"
fi

echo "==> TestFlight upload complete"
echo "    App ID:      $APP_STORE_APP_ID"
echo "    Scheme:      $SCHEME"
echo "    Version:     $MARKETING_VERSION"
echo "    Build:       $BUILD_NUMBER"
echo "    IPA:         $IPA_PATH"
if [[ -n "${build_id:-}" ]]; then
    echo "    Build record: $build_id"
fi
if [[ "$PROJECT_VERSION_BUMP_REQUIRED" == "1" ]]; then
    echo "    Next repo version: $PROJECT_VERSION_BUMP_TARGET"
fi
