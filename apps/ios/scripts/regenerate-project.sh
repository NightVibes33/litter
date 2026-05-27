#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$PROJECT_DIR/Litter.xcodeproj"
NESTED_PROJECT="$PROJECT_FILE/Litter.xcodeproj"
REPAIR_ONLY=0

while [ "$#" -gt 0 ]; do
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

if [ -d "$NESTED_PROJECT" ]; then
  echo "warning: found nested generated project at $NESTED_PROJECT" >&2
  echo "warning: removing nested generated project" >&2
  rm -rf "$NESTED_PROJECT"
  needs_regen=1
fi

if [ ! -f "$PROJECT_FILE/project.pbxproj" ]; then
  needs_regen=1
fi

if [ "$REPAIR_ONLY" -eq 1 ] && [ "$needs_regen" -eq 0 ]; then
  exit 0
fi

echo "==> Regenerating $PROJECT_FILE"
(
  cd "$PROJECT_DIR"
  xcodegen generate --spec project.yml
)

if [ -d "$NESTED_PROJECT" ]; then
  echo "error: nested project still exists at $NESTED_PROJECT" >&2
  exit 1
fi

# Fix StoreKit Configuration in scheme - xcodegen does not generate a valid reference.
SCHEME_FILE="$PROJECT_FILE/xcshareddata/xcschemes/Litter.xcscheme"
if [ -f "$SCHEME_FILE" ]; then
  TMP_SCHEME="$SCHEME_FILE.tmp"
  sed '/<StoreKitConfigurationFileReference/,/<\/StoreKitConfigurationFileReference>/d' "$SCHEME_FILE" > "$TMP_SCHEME"
  awk '
    /<\/LaunchAction>/ {
      print "      <StoreKitConfigurationFileReference"
      print "         identifier = \"../../Sources/Litter/Resources/TipJarProducts.storekit\">"
      print "      </StoreKitConfigurationFileReference>"
      print "   </LaunchAction>"
      next
    }
    { print }
  ' "$TMP_SCHEME" > "$SCHEME_FILE"
  rm -f "$TMP_SCHEME"
fi
