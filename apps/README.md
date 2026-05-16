# Apps

Platform-specific Litter applications live here.

- `ios/` is the primary SwiftUI app. `project.yml` is the XcodeGen source of truth, and the app owns the local iSH runtime, settings terminal, file workspace, wallpapers, PiP, CarPlay, Watch surfaces, and BuildKit UI.

Shared protocol/runtime code lives under `../shared/rust-bridge`.
