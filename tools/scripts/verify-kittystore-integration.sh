#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"
missing=0

fail() {
  echo "error: $1" >&2
  missing=1
}

require_path() {
  label="$1"
  rel="$2"
  if [ ! -e "$ROOT_DIR/$rel" ]; then
    fail "missing $label: $rel"
  fi
}

require_grep() {
  label="$1"
  pattern="$2"
  rel="$3"
  if ! grep -Fq -- "$pattern" "$ROOT_DIR/$rel"; then
    fail "missing $label in $rel: $pattern"
  fi
}

require_path "SideStore AltSign package" "ThirdParty/SideStore/AltSign"
require_path "SideStore minimuxer source" "ThirdParty/SideStore/minimuxer"
require_path "SideStore LocalDevVPN tunnel provider" "ThirdParty/SideStore/LocalDevVPN-TunnelProv"
require_path "Feather Zsign package" "ThirdParty/Feather/Zsign-Package"
require_path "KittyStore view" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_path "AltStore source verifier" "tools/scripts/verify-altstore-source.py"
require_path "BuildKit settings view" "apps/ios/Sources/Litter/Views/BuildKitSettingsView.swift"
require_path "SideStore account importer" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreAccountImport.swift"
require_path "SideStore signing bridge" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreSigningBridge.swift"
require_path "SideStore minimuxer bridge" "apps/ios/Sources/Litter/Models/KittyStoreMinimuxerBridge.swift"

require_grep "SideStore upstream commit provenance" "d292edffd1264918e6a83d3d2a0fb8cfde80e3ca" "ThirdParty/UPSTREAMS.md"
require_grep "Feather upstream commit provenance" "2320fd752864adaa9a173f9fc2f64ee9241e979e" "ThirdParty/UPSTREAMS.md"
require_grep "AltSign dynamic package dependency" "AltSign-Dynamic" "apps/ios/project.yml"
require_grep "AltSign dynamic embed" "embed: true" "apps/ios/project.yml"
require_grep "minimuxer bridge build" "tools/scripts/build-sidestore-minimuxer.sh" ".github/workflows/ios-unsigned-ipa.yml"
require_grep "minimuxer linked Swift flag" "KITTYSTORE_MINIMUXER_LINKED" ".github/workflows/ios-unsigned-ipa.yml"
require_grep "dynamic framework packaging guard" "Verify embedded dynamic frameworks" ".github/workflows/ios-unsigned-ipa.yml"
require_grep "AltStore source verifier workflow gate" "verify-altstore-source.py" ".github/workflows/ios-unsigned-ipa.yml"

require_grep "SideStore .sideconf UI import" "Import SideStore Account" "apps/ios/Sources/Litter/Views/BuildKitSettingsView.swift"
require_grep "SideStore .sideconf handler" "handleSideStoreAccountImport" "apps/ios/Sources/Litter/Views/BuildKitSettingsView.swift"
require_grep "SideStore local_user preservation" "local_user" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreAccountImport.swift"
require_grep "SideStore adiPB preservation" "adiPB" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreAccountImport.swift"
require_grep "SideStore ADI status" "hasSideStoreADI" "apps/ios/Sources/Litter/Models/NyxianSigningCertificateValidator.swift"
require_grep "SideStore ADI preserved after team save" "sideStoreAdiPB: account.sideStoreAdiPB" "apps/ios/Sources/Litter/Views/BuildKitSettingsView.swift"
require_grep "SideStore bot import command" "litter-kittystore-import-sideconf" "apps/ios/Sources/Litter/Models/LitterBuildKit.swift"

require_grep "Feather remove files UI" "Remove Files" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "KittyStore source checksum display" "shortSHA256" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "KittyStore source checksum verification" "sha256Hex(for: fileURL)" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "Feather app appearance option" "appAppearance" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "Feather minimum iOS option" "minimumAppRequirement" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "Feather remove files plan" "removeFiles" "apps/ios/Sources/Litter/Models/LitterBuildKit.swift"
require_grep "Feather native remove files" "LBIKittyStoreRemoveAppFiles" "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"
require_grep "Feather native appearance plist" "UIUserInterfaceStyle" "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"
require_grep "Feather native minimum OS plist" "MinimumOSVersion" "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"
require_grep "Feather native ProMotion plist" 'CADisableMinimumFrameDurationOnPhone"] = @YES' "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"

require_grep "README SideStore .sideconf docs" ".sideconf" "README.md"
require_grep "README SideStore/Feather attribution" "SideStore, AltStore, Feather, LocalDevVPN" "README.md"
require_grep "README installable AltSource versions" "version-history first" "README.md"

if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "KittyStore SideStore/Feather integration wiring verified."
