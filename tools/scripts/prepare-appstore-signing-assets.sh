#!/usr/bin/env bash
set -euo pipefail

: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${ASC_PRIVATE_KEY_PATH:?ASC_PRIVATE_KEY_PATH is required}"
: "${IOS_TEAM_ID:?IOS_TEAM_ID is required}"

CERTIFICATE_TYPE="${CERTIFICATE_TYPE:-DISTRIBUTION}"
REVOKE_EXISTING_LITTER_CI_DISTRIBUTION_CERTIFICATE_ON_LIMIT="${REVOKE_EXISTING_LITTER_CI_DISTRIBUTION_CERTIFICATE_ON_LIMIT:-0}"
REVOKE_EXISTING_DISTRIBUTION_CERTIFICATES_ON_LIMIT="${REVOKE_EXISTING_DISTRIBUTION_CERTIFICATES_ON_LIMIT:-0}"
REVOKE_NEWEST_DISTRIBUTION_CERTIFICATE_ON_LIMIT="${REVOKE_NEWEST_DISTRIBUTION_CERTIFICATE_ON_LIMIT:-0}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.sigkitten.litter.39A8Q3T3TR}"
LIVE_ACTIVITY_BUNDLE_ID="${LIVE_ACTIVITY_BUNDLE_ID:-${APP_BUNDLE_ID}.liveactivity}"
LIVEPROCESS_BUNDLE_ID="${LIVEPROCESS_BUNDLE_ID:-${APP_BUNDLE_ID}.liveprocess}"
WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-${APP_BUNDLE_ID}.watchkitapp}"
WATCH_COMP_BUNDLE_ID="${WATCH_COMP_BUNDLE_ID:-${APP_BUNDLE_ID}.watchkitapp.complications}"
RUN_LABEL="${GITHUB_RUN_ID:-local}-$(date +%Y%m%d%H%M%S)"
INCLUDE_LIVEPROCESS="${INCLUDE_LIVEPROCESS:-1}"
SIGNING_DIR="${RUNNER_TEMP:-/tmp}/litter-appstore-signing"
KEYCHAIN_PATH="${RUNNER_TEMP:-/tmp}/litter-appstore-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"

if [[ "$INCLUDE_LIVEPROCESS" != "0" && "$INCLUDE_LIVEPROCESS" != "1" ]]; then
    echo "INCLUDE_LIVEPROCESS must be 0 or 1." >&2
    exit 1
fi

mkdir -p "$SIGNING_DIR" "$HOME/Library/MobileDevice/Provisioning Profiles"

export ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_PATH

csr_key="$SIGNING_DIR/litter-appstore.key"
csr_path="$SIGNING_DIR/litter-appstore.csr"
cert_json="$SIGNING_DIR/certificate.json"
cert_path="$SIGNING_DIR/litter-appstore.cer"

openssl req -new -newkey rsa:2048 -nodes     -keyout "$csr_key"     -out "$csr_path"     -subj "/CN=Litter App Store CI $RUN_LABEL/O=$IOS_TEAM_ID/C=US" >/dev/null 2>&1

cert_error="$SIGNING_DIR/certificate-create.err"
create_certificate() {
    asc certificates create         --certificate-type "$CERTIFICATE_TYPE"         --csr "$csr_path"         --output json >"$cert_json" 2>"$cert_error"
}

revoke_litter_ci_distribution_certificates() {
    local existing_json="$SIGNING_DIR/existing-certificates.json"
    local existing_id matching_count
    local matching_ids=()

    asc certificates list --certificate-type "$CERTIFICATE_TYPE" --output json >"$existing_json"
    echo "Existing $CERTIFICATE_TYPE certificates:"
    jq -r '.data[]? | "- id=\(.id) name=\(.attributes.displayName // .attributes.name // "") type=\(.attributes.certificateType // .attributes.certificate_type // "") expires=\(.attributes.expirationDate // .attributes.expiration_date // "")"' "$existing_json"

    while IFS= read -r existing_id; do
        [[ -n "$existing_id" ]] || continue
        matching_ids+=("$existing_id")
    done < <(
        jq -r '.data[]? |
            select(((.attributes.displayName // .attributes.name // "") | tostring | contains("Litter App Store CI"))) |
            .id' "$existing_json"
    )

    matching_count="${#matching_ids[@]}"
    if [[ "$matching_count" -eq 0 && "$REVOKE_NEWEST_DISTRIBUTION_CERTIFICATE_ON_LIMIT" == "1" ]]; then
        echo "No Litter App Store CI $CERTIFICATE_TYPE certificates were found. Revoking the newest existing $CERTIFICATE_TYPE certificate as the previous generated CI certificate."
        while IFS= read -r existing_id; do
            [[ -n "$existing_id" ]] || continue
            matching_ids+=("$existing_id")
        done < <(
            jq -r '[.data[]? | { id: .id, expires: (.attributes.expirationDate // .attributes.expiration_date // "") }] | sort_by(.expires) | reverse | .[0].id // empty' "$existing_json"
        )
        matching_count="${#matching_ids[@]}"
    fi

    if [[ "$matching_count" -eq 0 && "$REVOKE_EXISTING_DISTRIBUTION_CERTIFICATES_ON_LIMIT" == "1" ]]; then
        if [[ "${ALLOW_REVOKE_ALL_DISTRIBUTION_CERTIFICATES_ON_LIMIT:-0}" != "1" ]]; then
            echo "No Litter App Store CI $CERTIFICATE_TYPE certificates were found." >&2
            echo "Refusing to revoke all existing $CERTIFICATE_TYPE certificates without ALLOW_REVOKE_ALL_DISTRIBUTION_CERTIFICATES_ON_LIMIT=1." >&2
            return 1
        fi
        echo "No Litter App Store CI $CERTIFICATE_TYPE certificates were found. Revoking all existing $CERTIFICATE_TYPE certificates because both REVOKE_EXISTING_DISTRIBUTION_CERTIFICATES_ON_LIMIT=1 and ALLOW_REVOKE_ALL_DISTRIBUTION_CERTIFICATES_ON_LIMIT=1."
        while IFS= read -r existing_id; do
            [[ -n "$existing_id" ]] || continue
            matching_ids+=("$existing_id")
        done < <(jq -r '.data[]? | .id' "$existing_json")
        matching_count="${#matching_ids[@]}"
    fi

    if [[ "$matching_count" -eq 0 ]]; then
        echo "No $CERTIFICATE_TYPE certificates were found to revoke." >&2
        return 1
    fi

    for existing_id in "${matching_ids[@]}"; do
        echo "Revoking stale Litter CI $CERTIFICATE_TYPE certificate: $existing_id"
        asc certificates revoke --id "$existing_id" --confirm >/dev/null
    done
}

if ! create_certificate; then
    echo "Certificate creation failed:" >&2
    cat "$cert_error" >&2
    if [[ "$REVOKE_EXISTING_LITTER_CI_DISTRIBUTION_CERTIFICATE_ON_LIMIT" == "1" ]] && \
        grep -Eiq 'current .*Distribution certificate|pending certificate request|certificate limit' "$cert_error"; then
        revoke_litter_ci_distribution_certificates
        create_certificate
    else
        exit 1
    fi
fi

cert_id="$(jq -r '.data.id // empty' "$cert_json")"
cert_content="$(jq -r '.data.attributes.certificateContent // .data.attributes.certificate_content // empty' "$cert_json")"
if [[ -z "$cert_id" || -z "$cert_content" ]]; then
    echo "Unable to create $CERTIFICATE_TYPE certificate from App Store Connect response." >&2
    cat "$cert_json" >&2
    exit 1
fi
printf '%s' "$cert_content" | base64 --decode >"$cert_path"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH"
security default-keychain -d user -s "$KEYCHAIN_PATH"
security import "$csr_key" -k "$KEYCHAIN_PATH" -T /usr/bin/codesign -T /usr/bin/security
security import "$cert_path" -k "$KEYCHAIN_PATH" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
identity_output="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH")"
printf '%s\n' "$identity_output"
repair_identity="$(
    printf '%s\n' "$identity_output" |
        awk '/Apple Distribution|iPhone Distribution/ { print $2; exit }'
)"
repair_identity="${repair_identity#\"}"
repair_identity="${repair_identity%\"}"
if [[ -z "$repair_identity" ]]; then
    echo "Unable to resolve generated distribution signing identity hash." >&2
    exit 1
fi
echo "CODESIGN_REPAIR_IDENTITY=$repair_identity" >>"$GITHUB_ENV"

bundle_ids_json="$SIGNING_DIR/bundle-ids.json"
asc bundle-ids list --paginate --output json >"$bundle_ids_json"

find_bundle_resource_id() {
    local identifier="$1"
    jq -r --arg identifier "$identifier" '.data[]? | select(.attributes.identifier == $identifier) | .id' "$bundle_ids_json" | head -n 1
}

create_and_install_profile() {
    local env_name="$1"
    local identifier="$2"
    local profile_name="$3"
    local bundle_resource_id profile_json profile_id profile_path profile_uuid profile_display

    bundle_resource_id="$(find_bundle_resource_id "$identifier")"
    if [[ -z "$bundle_resource_id" ]]; then
        echo "Missing App Store Connect bundle ID resource for $identifier" >&2
        exit 1
    fi

    profile_json="$SIGNING_DIR/${env_name}.json"
    profile_path="$SIGNING_DIR/${env_name}.mobileprovision"

    asc profiles create         --name "$profile_name"         --profile-type IOS_APP_STORE         --bundle "$bundle_resource_id"         --certificate "$cert_id"         --output json >"$profile_json"

    profile_id="$(jq -r '.data.id // empty' "$profile_json")"
    if [[ -z "$profile_id" ]]; then
        echo "Unable to create IOS_APP_STORE profile for $identifier" >&2
        cat "$profile_json" >&2
        exit 1
    fi

    asc profiles download --id "$profile_id" --output "$profile_path"
    profile_uuid="$(security cms -D -i "$profile_path" | plutil -extract UUID raw -)"
    profile_display="$(security cms -D -i "$profile_path" | plutil -extract Name raw -)"
    cp "$profile_path" "$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
    echo "$env_name=$profile_display" >>"$GITHUB_ENV"
    echo "Installed App Store profile for $identifier: $profile_display"
}

create_and_install_profile APP_PROVISIONING_PROFILE_SPECIFIER "$APP_BUNDLE_ID" "Litter App Store CI $RUN_LABEL"
create_and_install_profile LIVE_ACTIVITY_PROVISIONING_PROFILE_SPECIFIER "$LIVE_ACTIVITY_BUNDLE_ID" "Litter Live Activity App Store CI $RUN_LABEL"
if [[ "$INCLUDE_LIVEPROCESS" == "1" ]]; then
    create_and_install_profile LIVEPROCESS_PROVISIONING_PROFILE_SPECIFIER "$LIVEPROCESS_BUNDLE_ID" "Litter LiveProcess App Store CI $RUN_LABEL"
fi
create_and_install_profile WATCH_PROVISIONING_PROFILE_SPECIFIER "$WATCH_BUNDLE_ID" "Litter Watch App Store CI $RUN_LABEL"
create_and_install_profile WATCH_COMP_PROVISIONING_PROFILE_SPECIFIER "$WATCH_COMP_BUNDLE_ID" "Litter Watch Complications App Store CI $RUN_LABEL"

echo "APP_CODE_SIGN_IDENTITY=Apple Distribution" >>"$GITHUB_ENV"
echo "LIVE_ACTIVITY_CODE_SIGN_IDENTITY=Apple Distribution" >>"$GITHUB_ENV"
if [[ "$INCLUDE_LIVEPROCESS" == "1" ]]; then
    echo "LIVEPROCESS_CODE_SIGN_IDENTITY=Apple Distribution" >>"$GITHUB_ENV"
fi
echo "WATCH_CODE_SIGN_IDENTITY=Apple Distribution" >>"$GITHUB_ENV"
echo "WATCH_COMP_CODE_SIGN_IDENTITY=Apple Distribution" >>"$GITHUB_ENV"
echo "Prepared generated App Store signing assets with certificate $cert_id."
