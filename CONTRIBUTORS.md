# Contributors

This file credits the people and assisted tooling with accepted work in the
Litter history. It is based on the commit history and merged pull requests in
Daniel Nakov's original upstream repository, `dnakov/litter`, plus accepted
commits in this fork, `NightVibes33/litter`.

Last reviewed: 2026-05-17.

## Project Maintainers And Fork Work

| Contributor | What they provided |
|---|---|
| Daniel Nakov (`dnakov`) | Original creator and upstream maintainer of Litter. Built the core mobile app direction, including the iOS app, Android parity work, Rust bridge and Codex mobile client integration, session/thread handling, SSH and local Codex runtime wiring, discovery and pairing flows, iSH/Alpine local runtime work, realtime and voice features, themes, generative UI widgets, Live Activity and push-related work, release automation, TestFlight/App Store workflows, Android release flows, and the `kittylitter`/Alleycat bridge ecosystem. |
| NightVibes33 | Fork maintainer and distribution owner for `NightVibes33/litter`. Added and maintained the fork work around GitHub-runner BuildKit asset builds, private BuildKit asset download wiring, focused Nyxian BuildKit source import hardening, BuildKit IPA path wiring, local model workflow improvements, parallel CI work, model import/download detail screens, model picker clipping fixes, file workspace navigation restoration, and BuildKit wrapper/header staging fixes. |
| Zyn | Implemented major fork-side iOS runtime work, including the unsigned IPA build path, iOS skills bridge, AI provider and local model foundation, local fakefs file workspace, native llama token bridge, local model search/download/progress/validation flows, local model settings, local agent workspace, main-chat routing through local models, TurboQuant llama runtime integration, Nyxian BuildKit bridge import, private on-device Swift BuildKit asset path, native BuildKit wrapper, fakefs project staging for BuildKit, Swift shims, Swift toolchain self-test command, and several BuildKit install, rpath, driver loading, plist, and CI fixes. |
| Codex | AI-assisted implementation work recorded as commit author in this repository. Contributions include local model tool loop primitives, llama XCFramework CI, local model search downloads, BuildKit asset packaging and embedding fixes, BuildKit manifest encoding, ZIP extraction hardening, xcodebuild compatibility, Swift self-test verification, framework install-name normalization, fakefs diagnostics, local file browser/runtime UX improvements, goal command handling, and BuildKit risk coverage. |

## Accepted Upstream Contributors

These contributors have work present in `dnakov/litter` upstream history,
including merged pull requests or direct commits accepted into the original
repository.

| Contributor | What they provided |
|---|---|
| Maky (`makyinmars`) | Contributed multiple accepted mobile UX features: Android/iOS session UX improvements, iOS Codex RPC bridge coverage, mobile composer/session cleanup, Codex submodule exec-support work, workspace accordion/sidebar UX, skills/edit/rename/fork flows, improved tool-calling UX, picker cleanup, cross-platform agent identity and collaboration-target flows, thread/approval-flow improvements, iOS 18 support, Android/iOS search themes, server pill polish, SSH credential entry, system/light/dark theme mode, and AMP harness support. |
| Franklin | Provided early iOS/Android feature and cleanup work, including file search and command support, Android picker fixes, fork-specific identifier/signing metadata cleanup, session search, font and UX updates, model-list exposure, iOS exec hook path work for unified exec, app identifier cleanup, and CI/CD fixes around iOS builds. |
| sigkitten | Contributed mobile runtime, IPC, rendering, release, and Android work. Accepted commits include Android pets overlay, Codex 0.128 update work, provisioning and signing fixes for iOS device/release builds, server reconnect actions, source-thread notification routing, SSH wake/persist behavior, progressive session loading, IPC and connection-state handling, transcript chrome and thread reuse improvements, native mobile math parsing, iOS tests, Android permissions inheritance, Android wallpaper preview/effects fixes, Android back handling, realtime voice session reuse, ChatGPT OAuth browser handoff fixes, generative UI Rust migration, and UniFFI/Rust bridge surface cleanup. |
| tabrobotics | Contributed Android and OpenCode support work, including OpenCode mobile shell support, bundled Codex server and Node proxy work, GitHub Actions archive fallback, Gradle/lint fixes, OpenCode review feedback fixes, Android discovery sheet and local bridge connect flow fixes, Android image upload path fixes, iOS-style Android input bar/model selector improvements, and keyboard/border behavior fixes. |
| Kaynan Sampaio de Camargo (`kaynansc`) | Added and fixed settings and runtime-routing flows across iOS and Android: editable saved server connections, Android SSH credential prompt parity, reconnect/edit sheet behavior, dismissible Input Required modal, OpenAI base URL setting, active-thread scoped composer rate limits, thread-scoped input prompts, and routing approval/user-input responses back through the originating runtime channel. |
| D-DRUMROLL / Dixith-dev (`Dixith-dev`) | Improved Android UX and OpenCode support, including keyboard double-padding fixes, OpenCode mobile shell support, Android home/discovery/settings polish, centered Settings title in the Android popover, dropdown positioning fixes, and session deletion fixes on the home dashboard. |
| eagle.one / onegaop | Added folder grouping for sessions in the sidebar and related homepage screenshot documentation for the grouped-session UI. |
| kkellyoffical | Added Android conversation text selection support while keeping renderer scope limited, preserved message selection behavior, avoided duplicate markdown-ready callbacks, restored user-bubble styling, and helped stabilize Android JVM coverage around those changes. |
| Coy Geek (`coygeek`) | Added iOS transcript display controls and UI test coverage for transcript display behavior. |
| researchoor | Added completed-session row idle indicator support and fixed Live Activity timer cleanup when a session completes in the background. |
| Sina Rabiei (`nssina`) | Added Mac SSH setup documentation for exposing Codex sessions to Litter and updated README guidance around that flow. |
| Paul Pincente (`pincente`) | Improved Android large-screen and TV discovery behavior, including discovery modal layout and focus navigation. |
| Jason Penilla (`jpenilla`) | Added SSH detection for Codex installed through Bun. |
| Thomas Zarebczan (`tzarebczan`) | Restored and published Windows npm support for `kittylitter`. |
| frixa / frixaco | Improved SSH connection/bootstrap compatibility for Macs using Fish as the default shell. |
| ryanchen01 | Expanded the resolver SSH probe behavior. |
| shuv (`shuv1337`) | Fixed iOS theme JSON decoding to tolerate null/non-string values and `#RRGGBBAA` color values. |
| zulfaza | Added `~/.opencode/bin` to the SSH profile initialization PATH probe. |
| Benjamin Western | Improved the Pi over Alleycat transport baseline. |
| sliced-paraiba | Improved POSIX command portability by switching command invocation to `/usr/bin/env`. |

## Third-Party Project Credits

Litter also builds on third-party open-source projects. Their licenses remain
their own and are documented in `THIRD_PARTY_NOTICES.md`.

| Project | Role in Litter |
|---|---|
| OpenAI Codex (`openai/codex`) | Upstream Codex agent/runtime source used through the `shared/third_party/codex` submodule and local patches. |
| ProjectNyxian / Nyxian | Source import used for the on-device Swift BuildKit path. |
| ProjectNyxian / LLVM-On-iOS | Source import and build tooling used for iOS compiler/BuildKit asset work. |

## Notes

Names are normalized where the same contributor appears under multiple Git
author identities or email addresses. This file is a credit record; it is not a
copyright assignment, contributor license agreement, or legal opinion.
