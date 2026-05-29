#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/Litter.xcodeproj"
NESTED_PROJECT="$PROJECT_FILE/Litter.xcodeproj"
REPAIR_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repair-only)
      REPAIR_ONLY=1
      shift
      ;;
    *)
      echo "usage: $(basename "$0") [--repair-only]" >&2
      exit 1
      ;;
  esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found; install xcodegen first" >&2
  exit 1
fi

needs_regen=0

if [[ -d "$NESTED_PROJECT" ]]; then
  echo "warning: found nested generated project at $NESTED_PROJECT" >&2
  echo "warning: removing nested generated project" >&2
  rm -rf "$NESTED_PROJECT"
  needs_regen=1
fi

if [[ ! -f "$PROJECT_FILE/project.pbxproj" ]]; then
  needs_regen=1
fi

if [[ "$REPAIR_ONLY" -eq 1 && "$needs_regen" -eq 0 ]]; then
  exit 0
fi

echo "==> Regenerating $PROJECT_FILE"
(
  cd "$PROJECT_DIR"
  xcodegen generate --spec project.yml
)

if [[ -d "$NESTED_PROJECT" ]]; then
  echo "error: nested project still exists at $NESTED_PROJECT" >&2
  exit 1
fi

# Fix StoreKit Configuration in scheme — xcodegen doesn't generate a valid reference.
SCHEME_FILE="$PROJECT_FILE/xcshareddata/xcschemes/Litter.xcscheme"
if [[ -f "$SCHEME_FILE" ]]; then
  # Remove broken xcodegen-generated StoreKitConfigurationFileReference if present
  sed -i '' '/<StoreKitConfigurationFileReference/,/<\/StoreKitConfigurationFileReference>/d' "$SCHEME_FILE"
  # Insert correct one before </LaunchAction>
  sed -i '' 's|</LaunchAction>|      <StoreKitConfigurationFileReference\
         identifier = "../../Sources/Litter/Resources/TipJarProducts.storekit">\
      </StoreKitConfigurationFileReference>\
   </LaunchAction>|' "$SCHEME_FILE"
fi
