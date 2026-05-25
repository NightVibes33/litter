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

require_absent() {
  label="$1"
  pattern="$2"
  rel="$3"
  if grep -Fq -- "$pattern" "$ROOT_DIR/$rel"; then
    fail "unexpected $label in $rel: $pattern"
  fi
}

require_path "SideStore AltSign package" "ThirdParty/SideStore/AltSign"
require_path "SideStore minimuxer source" "ThirdParty/SideStore/minimuxer"
require_path "SideStore LocalDevVPN tunnel provider" "ThirdParty/SideStore/LocalDevVPN-TunnelProv"
require_path "SideStore full source clone" "ThirdParty/SideStore/Source/AltStore/TabBarController.swift"
require_path "Feather full source clone" "ThirdParty/Feather/Source/Feather/Views/Signing/SigningView.swift"
require_path "LocalDevVPN full source clone" "ThirdParty/SideStore/LocalDevVPN-Source/TunnelProv/PacketTunnelProvider.swift"
require_path "Feather Zsign package" "ThirdParty/Feather/Zsign-Package"
require_path "KittyStore view" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_path "AltStore source verifier" "tools/scripts/verify-altstore-source.py"
require_path "BuildKit settings view" "apps/ios/Sources/Litter/Views/BuildKitSettingsView.swift"
require_path "SideStore account importer" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreAccountImport.swift"
require_path "SideStore signing bridge" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreSigningBridge.swift"
require_path "SideStore minimuxer bridge" "apps/ios/Sources/Litter/Models/KittyStoreMinimuxerBridge.swift"
require_path "KittyStore release source config" "apps/ios/Sources/Litter/Models/AppReleaseSource.swift"
require_path "SideStore TabBarController app reference" "ThirdParty/SideStore/AppReference/AltStore/TabBarController.swift"
require_path "SideStore Browse app reference" "ThirdParty/SideStore/AppReference/AltStore/Browse/BrowseViewController.swift"
require_path "SideStore My Apps app reference" "ThirdParty/SideStore/AppReference/AltStore/My Apps/MyAppsViewController.swift"
require_path "SideStore Sources app reference" "ThirdParty/SideStore/AppReference/AltStore/Sources/SourcesViewController.swift"
require_path "SideStore Settings app reference" "ThirdParty/SideStore/AppReference/AltStore/Settings/SettingsViewController.swift"
require_path "Feather OptionsManager app reference" "ThirdParty/Feather/AppReference/Feather/Backend/Observable/OptionsManager.swift"
require_path "Feather SigningHandler app reference" "ThirdParty/Feather/AppReference/Feather/Utilities/Handlers/SigningHandler.swift"
require_path "Feather TweakHandler app reference" "ThirdParty/Feather/AppReference/Feather/Utilities/Handlers/TweakHandler.swift"
require_path "Feather ZsignHandler app reference" "ThirdParty/Feather/AppReference/Feather/Utilities/Handlers/ZsignHandler.swift"
require_path "Feather SigningView app reference" "ThirdParty/Feather/AppReference/Feather/Views/Signing/SigningView.swift"
require_path "Feather SigningProperties app reference" "ThirdParty/Feather/AppReference/Feather/Views/Signing/SigningPropertiesView.swift"

require_grep "SideStore upstream commit provenance" "d292edffd1264918e6a83d3d2a0fb8cfde80e3ca" "ThirdParty/UPSTREAMS.md"
require_grep "Feather upstream commit provenance" "2320fd752864adaa9a173f9fc2f64ee9241e979e" "ThirdParty/UPSTREAMS.md"
require_grep "SideStore full source provenance" "SideStore full source snapshot path" "ThirdParty/UPSTREAMS.md"
require_grep "Feather full source provenance" "Feather full source snapshot path" "ThirdParty/UPSTREAMS.md"
require_grep "LocalDevVPN full source provenance" "LocalDevVPN full source snapshot path" "ThirdParty/UPSTREAMS.md"
require_grep "SideStore app reference provenance" "SideStore app layout reference snapshot path" "ThirdParty/UPSTREAMS.md"
require_grep "Feather app reference provenance" "Feather app reference snapshot path" "ThirdParty/UPSTREAMS.md"
require_grep "SideStore full source install path" "AppManager.shared.installAsync" "ThirdParty/SideStore/Source/AltStore/Browse/BrowseViewController.swift"
require_grep "Feather full source start signing" "Start Signing" "ThirdParty/Feather/Source/Feather/Views/Signing/SigningView.swift"
require_grep "LocalDevVPN full source tunnel provider" "PacketTunnelProvider" "ThirdParty/SideStore/LocalDevVPN-Source/TunnelProv/PacketTunnelProvider.swift"
require_grep "SideStore Browse reference install path" "AppManager.shared.installAsync" "ThirdParty/SideStore/AppReference/AltStore/Browse/BrowseViewController.swift"
require_grep "SideStore My Apps refresh reference" "AppManager.shared.refresh" "ThirdParty/SideStore/AppReference/AltStore/My Apps/MyAppsViewController.swift"
require_grep "SideStore Sources reference" "navigationItem.title" "ThirdParty/SideStore/AppReference/AltStore/Sources/SourcesViewController.swift"
require_grep "SideStore Settings certificate export reference" "SideStoreSigningCertificate.p12" "ThirdParty/SideStore/AppReference/AltStore/Settings/SettingsViewController.swift"
require_grep "Feather SigningView start button reference" "Start Signing" "ThirdParty/Feather/AppReference/Feather/Views/Signing/SigningView.swift"
require_grep "Feather SigningView advanced options reference" "NavigationLink(.localized" "ThirdParty/Feather/AppReference/Feather/Views/Signing/SigningView.swift"
require_grep "Feather Options remove files reference" "var removeFiles" "ThirdParty/Feather/AppReference/Feather/Backend/Observable/OptionsManager.swift"
require_grep "Feather Zsign reference" "Zsign.sign" "ThirdParty/Feather/AppReference/Feather/Utilities/Handlers/ZsignHandler.swift"
require_grep "KittyStore runtime source config command" "litter-kittystore-config" "apps/ios/Sources/Litter/Models/LitterBuildKit.swift"
require_grep "KittyStore source override persistence" "AppReleaseSource.saveOverrides" "apps/ios/Sources/Litter/Models/LitterBuildKit.swift"
require_grep "KittyStore source override reset" "AppReleaseSource.clearOverrides" "apps/ios/Sources/Litter/Models/LitterBuildKit.swift"
require_grep "KittyStore AppReleaseSource override keys" "ownerKey" "apps/ios/Sources/Litter/Models/AppReleaseSource.swift"
require_grep "Swift -e compatibility handler" "swift-e-check-ok" "apps/ios/Sources/Litter/Models/LitterBuildKit.swift"
require_grep "AltSign dynamic package dependency" "AltSign-Dynamic" "apps/ios/project.yml"
require_grep "AltSign dynamic embed" "embed: true" "apps/ios/project.yml"
require_grep "minimuxer bridge build" "tools/scripts/build-sidestore-minimuxer.sh" ".github/workflows/ios-unsigned-ipa.yml"
require_grep "minimuxer linked Swift flag" "KITTYSTORE_MINIMUXER_LINKED" ".github/workflows/ios-unsigned-ipa.yml"
require_grep "dynamic framework packaging guard" "Verify embedded dynamic frameworks" ".github/workflows/ios-unsigned-ipa.yml"
require_grep "Private BuildKit native refresh" "refresh_native_driver_if_needed" "apps/ios/scripts/prepare-buildkit-assets.sh"
require_grep "Private BuildKit native rebuild script" "build-litter-buildkit-native.sh" "apps/ios/scripts/prepare-buildkit-assets.sh"
require_grep "Private BuildKit refreshed fingerprint" "nativeDriverSourceFingerprint" "apps/ios/scripts/prepare-buildkit-assets.sh"
require_grep "AltStore source verifier workflow gate" "verify-altstore-source.py" ".github/workflows/ios-unsigned-ipa.yml"

require_grep "KittyStore configurable release source" "AppReleaseSource.current" "apps/ios/Sources/Litter/Models/AppUpdateStore.swift"
require_grep "BuildKit configurable KittyStore source" "AppReleaseSource.current.stableSourceURLString" "apps/ios/Sources/Litter/Models/LitterBuildKit.swift"
require_absent "hardcoded AppUpdateStore NightVibes repo URL" "github.com/NightVibes33/litter" "apps/ios/Sources/Litter/Models/AppUpdateStore.swift"
require_absent "hardcoded BuildKit KittyStore NightVibes repo URL" "github.com/NightVibes33/litter" "apps/ios/Sources/Litter/Models/LitterBuildKit.swift"

require_grep "KittyStore-owned SideStore .sideconf UI import" "Import SideStore Account" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "KittyStore-owned SideStore .sideconf handler" "importSideStoreAccount" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "KittyStore-owned Apple ID login" "saveKittyStoreAppleID" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "KittyStore-owned certificate import" "saveImportedCertificate" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "KittyStore settings certificate validation" "Validate & Save Certificate" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_absent "BuildKit SideStore account UI scatter" "Import SideStore Account" "apps/ios/Sources/Litter/Views/BuildKitSettingsView.swift"
require_absent "BuildKit Apple ID login UI scatter" "Login Apple ID" "apps/ios/Sources/Litter/Views/BuildKitSettingsView.swift"
require_absent "BuildKit certificate import UI scatter" "Import SideStore Certificate" "apps/ios/Sources/Litter/Views/BuildKitSettingsView.swift"
require_absent "KittyStore Litter updater dependency" "AppUpdateStore" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_absent "KittyStore Litter updater panel" "Featured Build" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "KittyStore real LocalDevVPN launcher" "localdevvpn://" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "SideStore local_user preservation" "local_user" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreAccountImport.swift"
require_grep "SideStore adiPB preservation" "adiPB" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreAccountImport.swift"
require_grep "SideStore ADI status" "hasSideStoreADI" "apps/ios/Sources/Litter/Models/NyxianSigningCertificateValidator.swift"
require_grep "SideStore ADI preserved after team save" "sideStoreAdiPB: account.sideStoreAdiPB" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "SideStore bot import command" "litter-kittystore-import-sideconf" "apps/ios/Sources/Litter/Models/LitterBuildKit.swift"

require_grep "Feather remove files UI" "Remove Files" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "KittyStore source checksum display" "shortSHA256" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "KittyStore source checksum verification" "sha256Hex(for: fileURL)" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "KittyStore source size verification" "Downloaded IPA size mismatch" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "SideStore AltSign fresh certificate validation" "The saved .p12 or provisioning profile is no longer valid" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "SideStore bridge certificate validation" "sidestore-certificate-validation-failed" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreSigningBridge.swift"
require_grep "SideStore imported certificate IPA preparation" "prepareSideStoreImportedIdentitySigningInput" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreSigningBridge.swift"
require_grep "SideStore signing metadata rewrite" "CFBundleShortVersionString" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreSigningBridge.swift"
require_absent "SideStore imported certificate direct IPA copy signing" "try fileManager.copyItem(at: ipaURL, to: outputURL)" "apps/ios/Sources/Litter/Models/KittyStoreSideStoreSigningBridge.swift"
require_grep "Feather app appearance option" "appAppearance" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "Feather minimum iOS option" "minimumAppRequirement" "apps/ios/Sources/Litter/Views/KittyStoreView.swift"
require_grep "Feather remove files plan" "removeFiles" "apps/ios/Sources/Litter/Models/LitterBuildKit.swift"
require_grep "Feather native remove files" "LBIKittyStoreRemoveAppFiles" "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"
require_grep "Feather native appearance plist" "UIUserInterfaceStyle" "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"
require_grep "Feather native minimum OS plist" "MinimumOSVersion" "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"
require_grep "Feather native ProMotion plist" 'CADisableMinimumFrameDurationOnPhone"] = @YES' "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"
require_grep "Feather native injection path mapper" "LBIKittyStoreDylibLoadPath" "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"
require_grep "Feather native inject into extensions" "LBIKittyStoreExtensionBundlePaths" "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"
require_grep "Feather native injection failure status" "kittystore-dylib-injection-failed" "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"
require_absent "Feather native injection path unapplied warning" "recorded but not applied by this backend" "ThirdParty/Nyxian/LitterBuildKitNative/LitterBuildKitInProcess.mm"

require_grep "README SideStore .sideconf docs" ".sideconf" "README.md"
require_grep "README full SideStore source docs" "ThirdParty/SideStore/Source" "README.md"
require_grep "README full Feather source docs" "ThirdParty/Feather/Source" "README.md"
require_grep "README full LocalDevVPN source docs" "ThirdParty/SideStore/LocalDevVPN-Source" "README.md"
require_grep "Notices full SideStore source" "ThirdParty/SideStore/Source" "THIRD_PARTY_NOTICES.md"
require_grep "Notices full Feather source" "ThirdParty/Feather/Source" "THIRD_PARTY_NOTICES.md"
require_grep "Notices full LocalDevVPN source" "ThirdParty/SideStore/LocalDevVPN-Source" "THIRD_PARTY_NOTICES.md"
require_grep "README real LocalDevVPN launcher" "localdevvpn://" "README.md"
require_grep "README SideStore/Feather attribution" "SideStore, AltStore, Feather, LocalDevVPN" "README.md"
require_grep "README installable AltSource versions" "version-history first" "README.md"

if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "KittyStore SideStore/Feather integration wiring verified."
