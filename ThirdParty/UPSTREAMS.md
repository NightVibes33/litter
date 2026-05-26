# Vendored Upstreams

These source drops are kept small and source-only. Generated build products, IPAs, provisioning profiles, certificates, and private assets are intentionally excluded.

## Feather / Zsign

- Feather reference repo: https://github.com/khcrysalis/Feather.git
- Feather reference commit inspected for this integration: `2320fd752864adaa9a173f9fc2f64ee9241e979e`
- Feather full source snapshot path: `ThirdParty/Feather/Source`
- Feather full source submodules are populated inside that snapshot, not left as empty placeholders:
  - `Zsign` from khcrysalis/Zsign-Package at `6ffe703df73ef9069adacdbb19d571f11a69a801`
  - `IDeviceKitten` from khcrysalis/IDeviceKit at `837cf1e14d4875771dd5ee1b754a4c86215c5db3`
- Feather app reference snapshot path: `ThirdParty/Feather/AppReference`
- KittyStore signing option reference files adapted from Feather at the inspected commit:
  - `Feather/Backend/Observable/OptionsManager.swift`
  - `Feather/Utilities/Handlers/SigningHandler.swift`
  - `Feather/Utilities/Handlers/TweakHandler.swift`
  - `Feather/Utilities/Handlers/ZsignHandler.swift`
  - `Feather/Views/Signing/SigningView.swift`
  - `Feather/Views/Signing/SigningPropertiesView.swift`
- Vendored signing engine repo: https://github.com/khcrysalis/Zsign-Package.git
- Vendored path: `ThirdParty/Feather/Zsign-Package`
- License: MIT, see `ThirdParty/Feather/Zsign-Package/LICENSE`

## SideStore / Minimuxer / LocalDevVPN

- SideStore reference repo: https://github.com/SideStore/SideStore.git
- SideStore reference commit inspected for this integration: `d292edffd1264918e6a83d3d2a0fb8cfde80e3ca`
- SideStore full source snapshot path: `ThirdParty/SideStore/Source`
- SideStore full source submodules are populated inside that snapshot, not left as empty placeholders:
  - `Dependencies/AltSign` at `7efe511440cfdbddc04a723490def86232c42f6c`
  - `Dependencies/minimuxer` at `e3614068c77fb09945eff363fbc3f9e8abf4c834`
  - `Dependencies/em_proxy` at `816dc73350dd456a24232963db77a3064fd9af8a`
  - `Dependencies/apps-v2.json` at `9724b1c56d9c339ceefe2197abfbc026cd4cc1ff`
  - `Dependencies/Roxas` at `0784711ed9a3a0bdb5cc57bde35d2c621691cf74`
  - `Dependencies/MarkdownAttributedString` at `750e8d5cb455dcc592a9b6d1cacaa19837e7abff`
  - `Dependencies/libimobiledevice` at `e7cc53a65b0f975754760032015f58dfbb87e1a0`
  - `Dependencies/libplist` at `258d3c24aa05ade06aac4b5dd5148fd04c02893e`
  - `Dependencies/libusbmuxd` at `30e678d4e76a9f4f8a550c34457dab73909bdd92`
  - `Dependencies/libimobiledevice-glue` at `214bafdde6a1434ead87357afe6cb41b32318495`
- SideStore app layout reference snapshot path: `ThirdParty/SideStore/AppReference`
- AltSign signing package repo: https://github.com/SideStore/AltSign.git
- AltSign submodule commit: `7efe511440cfdbddc04a723490def86232c42f6c`
- AltSign submodule path: `ThirdParty/SideStore/AltSign`
- minimuxer repo: https://github.com/SideStore/minimuxer.git
- minimuxer vendored commit: `f9432a085b19de1bbcd744c600f510f499703a97`
- minimuxer vendored path: `ThirdParty/SideStore/minimuxer`
- rusty_libimobiledevice repo: https://github.com/SideStore/rusty_libimobiledevice.git
- rusty_libimobiledevice vendored commit: `6a556c63b6d7f905e17b62d302086c93b0fddef8`
- rusty_libimobiledevice vendored path: `ThirdParty/SideStore/rusty_libimobiledevice`
- plist_plus repo: https://github.com/jkcoxson/plist_plus.git
- plist_plus vendored version: `0.2.6`
- plist_plus vendored path: `ThirdParty/SideStore/plist_plus`
- libtatsu repo: https://github.com/libimobiledevice/libtatsu.git
- libtatsu is cloned and built by the vendored rusty_libimobiledevice build script.
- Minimuxer wrapper path: `ThirdParty/SideStore/MinimuxerWrapper.swift`
- KittyStore layout reference files adapted from SideStore at the inspected commit:
  - `AltStore/TabBarController.swift`
  - `AltStore/Browse/BrowseViewController.swift`
  - `AltStore/My Apps/MyAppsViewController.swift`
  - `AltStore/Sources/SourcesViewController.swift`
  - `AltStore/Settings/SettingsViewController.swift`
- LocalDevVPN repo: https://github.com/jkcoxson/LocalDevVPN.git
- LocalDevVPN vendored commit: `c4566ce08931cef414c9f656e7e33c66bdb2454e`
- LocalDevVPN full source snapshot path: `ThirdParty/SideStore/LocalDevVPN-Source`
- LocalDevVPN tunnel-provider path: `ThirdParty/SideStore/LocalDevVPN-TunnelProv`
- License: minimuxer is AGPL-3.0, see `ThirdParty/SideStore/minimuxer/LICENSE`; rusty_libimobiledevice, plist_plus, and libtatsu are LGPL-2.1-or-later; LocalDevVPN keeps its upstream terms.

## Ghostty

- Ghostty renderer repo: https://github.com/ghostty-org/ghostty.git
- Ghostty submodule commit: `a968e120dd084bd886239d1cac938f0177f019d9`
- Ghostty submodule path: `shared/third_party/ghostty`
- Litter mobile embedding patch: `patches/ghostty/litter-mobile-embed.patch`
- License: see `shared/third_party/ghostty/LICENSE` when the submodule is checked out.
