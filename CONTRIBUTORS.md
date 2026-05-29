# Contributors And Credits

This is the source-backed credit record for Litter. It records what each
person or tool provided, not just a list of names.

Reviewed on: 2026-05-25

## License Status

Litter is open source, but it is not MIT licensed. The main project license is
GPLv3 with an additional GPLv3 section 7 permission for Apple App Store and
Google Play distribution. See `LICENSE` for the full terms.

Third-party projects keep their own licenses. See `THIRD_PARTY_NOTICES.md`.

## Audit Basis

Credits were checked against these sources:

- `dnakov/litter`, Daniel Nakov's original upstream repository, at
  `upstream/main` commit `3fd94228`.
- `NightVibes33/litter`, this fork, at `origin/main` commit `b424eb2b` before
  this upstream sync.
- GitHub merged pull request metadata from `dnakov/litter`.
- `git log` author history for both `upstream/main` and the fork-only range
  `upstream/main..origin/main`.

Most upstream pull requests were merged by Daniel Nakov (`dnakov`). Two
accepted upstream PRs, #77 and #78, are reported by GitHub as merged by
`Dixith-dev`; they are still credited because the work is present in Daniel's
original upstream repository history.

## Project Maintainers And Fork Contributors

| Contributor | What they provided |
|---|---|
| Daniel Nakov (`dnakov`) | Original creator and upstream maintainer. Built and maintained the main Litter mobile codebase: iOS app architecture, Android parity, Rust/Codex bridge, session and thread state, SSH/local Codex runtime, iSH/Alpine runtime work, discovery/pairing, realtime and voice features, themes, generative UI widgets, Live Activity/push work, release automation, App Store/TestFlight flows, Android release flows, and `kittylitter`/Alleycat bridge work. |
| NightVibes33 | Maintains this fork and distribution repo. Fork-only commits added or maintained GitHub-runner BuildKit asset builds, private BuildKit asset downloads, focused Nyxian BuildKit import hardening, BuildKit IPA wiring, local model workflow improvements, parallel CI, model import/download UX, model picker clipping fixes, file workspace navigation restoration, and BuildKit wrapper/header staging fixes. |
| Zyn | Added a large part of the fork-side iOS runtime work: unsigned IPA workflow, iOS skills bridge, AI provider and local model foundation, real local fakefs file workspace, local model imports/downloads/progress/validation/settings, native llama token bridge, TurboQuant llama runtime work, local agent workspace, main-chat routing through local models, Nyxian BuildKit bridge import, private on-device Swift BuildKit asset path, native BuildKit wrapper, fakefs project staging for BuildKit, Swift shims, Swift self-test command, and BuildKit install/rpath/driver/plist/CI fixes. |
| Codex | AI-assisted implementation commits recorded in Git history. Fork-side work includes local model tool loop primitives, llama XCFramework CI, local model search/downloads, BuildKit asset packaging and embedding hardening, manifest encoding, ZIP extraction hardening, xcodebuild compatibility, Swift self-test verification, framework install-name normalization, fakefs diagnostics, local file browser/runtime UX, goal command handling, and BuildKit risk coverage. |

## Accepted Upstream Pull Requests

These PRs were accepted into Daniel Nakov's original upstream repository. They
are the clearest evidence for externally contributed work accepted into
the original project.

| Contributor | Accepted PRs | What they provided |
|---|---|---|
| Maky (`makyinmars`) | [#3](https://github.com/dnakov/litter/pull/3), [#4](https://github.com/dnakov/litter/pull/4), [#10](https://github.com/dnakov/litter/pull/10), [#11](https://github.com/dnakov/litter/pull/11), [#13](https://github.com/dnakov/litter/pull/13), [#14](https://github.com/dnakov/litter/pull/14), [#26](https://github.com/dnakov/litter/pull/26), [#99](https://github.com/dnakov/litter/pull/99), [#101](https://github.com/dnakov/litter/pull/101), [#124](https://github.com/dnakov/litter/pull/124), [#145](https://github.com/dnakov/litter/pull/145) | Improved Android/iOS session UX, mobile composer UX, iOS Codex RPC bridge coverage, Codex submodule exec support, workspace accordion/sidebar UX, skills/edit/rename/fork flows, tool-calling UX, picker UX, cross-platform agent identity and collaboration targets, remote-host agent logos, thread/approval flow, iOS 18 support, Android/iOS search themes, server pill polish, SSH credential entry, system/light/dark theme mode, and AMP support. |
| D-DRUMROLL / Dixith-dev (`Dixith-dev`) | [#7](https://github.com/dnakov/litter/pull/7), [#24](https://github.com/dnakov/litter/pull/24), [#44](https://github.com/dnakov/litter/pull/44), [#77](https://github.com/dnakov/litter/pull/77), [#78](https://github.com/dnakov/litter/pull/78) | Fixed Android keyboard double padding, added Android OpenCode mobile shell support, overhauled Android home/discovery/settings flows, centered the Android Settings popover title, fixed Android dropdown menu positioning, and fixed home-dashboard session deletion. |
| Kaynan Sampaio de Camargo (`kaynansc`) | [#109](https://github.com/dnakov/litter/pull/109), [#111](https://github.com/dnakov/litter/pull/111), [#114](https://github.com/dnakov/litter/pull/114), [#116](https://github.com/dnakov/litter/pull/116), [#117](https://github.com/dnakov/litter/pull/117), [#118](https://github.com/dnakov/litter/pull/118) | Added editable saved server connections, Android SSH credential prompt parity, reconnect/edit-sheet behavior, dismissible Input Required modal, OpenAI base URL setting, active-thread scoped rate-limit behavior, thread-scoped input prompts, and correct routing for approval/user-input responses through the originating runtime channel. |
| researchoor | [#45](https://github.com/dnakov/litter/pull/45), [#46](https://github.com/dnakov/litter/pull/46) | Fixed Live Activity timer cleanup when a background session completes and added an idle indicator dot for completed session rows. |
| Coy Geek (`coygeek`) | [#130](https://github.com/dnakov/litter/pull/130) | Added iOS transcript display controls and UI coverage for transcript display behavior. |
| Niklas Sheth | [#153](https://github.com/dnakov/litter/pull/153) | Fixed iOS composer editing behavior so selection is not forcibly reset while the user is editing text. |
| eagle.one / onegaop | [#9](https://github.com/dnakov/litter/pull/9) | Added folder grouping for sessions in the sidebar. Direct accepted commits also added iPhone simulator screenshots and homepage screenshot documentation for that UI. |
| kkellyoffical | [#82](https://github.com/dnakov/litter/pull/82) | Added Android conversation text selection support, kept renderer scope constrained, preserved message selection, avoided duplicate markdown-ready callbacks, restored user bubble styling, and stabilized Android JVM tests around those changes. |
| Sina Rabiei (`nssina`) | [#12](https://github.com/dnakov/litter/pull/12) | Added Mac SSH setup documentation for exposing Codex sessions in Litter and updated README guidance for that flow. |
| Paul Pincente (`pincente`) | [#5](https://github.com/dnakov/litter/pull/5) | Improved Android large-screen discovery modal layout and TV focus navigation. |
| frixa / frixaco | [#73](https://github.com/dnakov/litter/pull/73) | Improved SSH connection/bootstrap compatibility for Macs using Fish as the default shell. |
| ryanchen01 | [#75](https://github.com/dnakov/litter/pull/75) | Expanded resolver SSH probe behavior. |
| Jason Penilla (`jpenilla`) | [#80](https://github.com/dnakov/litter/pull/80) | Added SSH detection for Codex installed through Bun. |
| Thomas Zarebczan (`tzarebczan`) | [#104](https://github.com/dnakov/litter/pull/104) | Brought back Windows npm publishing support for `kittylitter`. |
| shuv (`shuv1337`) | [#107](https://github.com/dnakov/litter/pull/107) | Fixed iOS theme JSON decoding so null/non-string values and `#RRGGBBAA` colors are tolerated. |
| zulfaza | [#125](https://github.com/dnakov/litter/pull/125) | Added `~/.opencode/bin` to the SSH profile initialization PATH probe. |
| Benjamin Western | [#137](https://github.com/dnakov/litter/pull/137) | Improved the Pi over Alleycat transport baseline. |
| sliced-paraiba | [#139](https://github.com/dnakov/litter/pull/139) | Improved POSIX command portability by switching command invocation to `/usr/bin/env`. |

## Daniel Nakov Upstream PRs

Daniel also landed substantial self-authored PRs in the original upstream
repository. These are not external credits, but they are important to the app's
history.

| Area | Accepted PRs |
|---|---|
| Android parity and theme/icon alignment | [#2](https://github.com/dnakov/litter/pull/2) |
| iOS UI, auth, local runtime, keyboard, OAuth, light mode, fonts, rate limits, voice transcription, SSH bootstrap | [#15](https://github.com/dnakov/litter/pull/15), [#16](https://github.com/dnakov/litter/pull/16), [#17](https://github.com/dnakov/litter/pull/17), [#18](https://github.com/dnakov/litter/pull/18), [#19](https://github.com/dnakov/litter/pull/19), [#20](https://github.com/dnakov/litter/pull/20), [#21](https://github.com/dnakov/litter/pull/21), [#22](https://github.com/dnakov/litter/pull/22) |
| Themes, appearance, Live Activity, push proxy, generative UI, home dashboard, transcript, Textual migration, sheet state injection | [#25](https://github.com/dnakov/litter/pull/25), [#27](https://github.com/dnakov/litter/pull/27), [#29](https://github.com/dnakov/litter/pull/29), [#30](https://github.com/dnakov/litter/pull/30) |
| Reverse-proxy WebSocket support, local stdio runtime, simulator shell hardening, subagent/session UI, image/paste turn input | [#32](https://github.com/dnakov/litter/pull/32), [#33](https://github.com/dnakov/litter/pull/33), [#34](https://github.com/dnakov/litter/pull/34), [#35](https://github.com/dnakov/litter/pull/35), [#42](https://github.com/dnakov/litter/pull/42) |
| Rust store boundary, runtime parity, mobile release automation, CI cache/release work, mobile runtime followups, autoscroll, collapsed transcript previews, TestFlight release splitting | [#48](https://github.com/dnakov/litter/pull/48), [#51](https://github.com/dnakov/litter/pull/51), [#52](https://github.com/dnakov/litter/pull/52), [#53](https://github.com/dnakov/litter/pull/53), [#54](https://github.com/dnakov/litter/pull/54), [#55](https://github.com/dnakov/litter/pull/55), [#56](https://github.com/dnakov/litter/pull/56), [#57](https://github.com/dnakov/litter/pull/57), [#58](https://github.com/dnakov/litter/pull/58), [#59](https://github.com/dnakov/litter/pull/59), [#60](https://github.com/dnakov/litter/pull/60), [#61](https://github.com/dnakov/litter/pull/61), [#62](https://github.com/dnakov/litter/pull/62), [#63](https://github.com/dnakov/litter/pull/63) |
| Android OAuth, markdown math rendering, discovery pairing, watch, terminal, Ghostty, and release followups | [#132](https://github.com/dnakov/litter/pull/132), [#133](https://github.com/dnakov/litter/pull/133), [#143](https://github.com/dnakov/litter/pull/143) plus direct upstream commits through `3fd94228` |

## Accepted Direct Upstream Commit Authors

Some contributors also appear as accepted Git authors in `upstream/main` outside
or in addition to the PR author list. These are credited because their commits
are present in the original upstream history.

| Contributor | Accepted direct commit evidence |
|---|---|
| Franklin | File search and commands for iOS/Android, Android picker fixes, app identifier and signing metadata cleanup, session search, font/UX updates, model list exposure, iOS exec hook path for unified exec, iOS 18 support work, search theme work, and iOS CI/CD fixes. |
| sigkitten | Mobile IPC and connection-state work, progressive session loading, transcript chrome/thread reuse, permission handling, native mobile math parsing and iOS tests, Android permissions/wallpaper/back/OAuth/realtime fixes, generative UI Rust migration, UniFFI/Rust bridge surface cleanup, iOS signing/provisioning, reconnect actions, source-thread notifications, and Android pets overlay. |
| Daniel Nakov (`dnakov`) | Recent direct upstream commits through `3fd94228`: Ghostty renderer terminal work, Android proot/Ghostty build targets, watch UI/complication/App Intent work, discovery pairing import, triaged crash-path fixes, trusted publishing workflow updates, and the fetchable Ghostty submodule pin. |
| tabrobotics | Android OpenCode/mobile shell implementation details, bundled Codex server and Node proxy work, Android discovery/local bridge fixes, GitHub Actions archive fallback, Gradle/lint fixes, Android image upload path fixes, and Android input bar/model selector polish. |
| eagle.one | Session-folder grouping implementation and screenshot/homepage documentation commits around that feature. |

## Fork-Only Accepted Work

These credits come from the fork-only range `upstream/main..origin/main`.

| Contributor | Accepted fork-only work |
|---|---|
| NightVibes33 | BuildKit asset CI defaults and gating, faster BuildKit asset reuse, Nyxian header staging for the BuildKit wrapper, file workspace navigation restoration, local model workflow and parallel CI improvements, BuildKit asset link from unsigned IPA workflow, GitHub-runner BuildKit asset builds, focused Nyxian BuildKit source import hardening/stabilization, BuildKit IPA path wiring, green BuildKit asset build documentation, private BuildKit asset downloads, attachment/model download compile fixes, model picker label clipping fix, and real import/model download details. |
| Zyn | Unsigned IPA workflow and iOS skills bridge, mobile workflow tolerance for missing sccache secrets, AI provider/local model foundation, local fakefs file workspace and write hardening, nonblocking local model imports, local model download/search/progress/validation, native llama token bridge, local model settings and local agent workspace, main-chat local model routing, TurboQuant llama fork build/integration, advanced llama options, Nyxian BuildKit bridge import, private Swift BuildKit asset path, native BuildKit wrapper, fakefs BuildKit project staging, BuildKit wrapper documentation, Swift shims and self-test, BuildKit asset install/rpath/driver/plist/CI fixes, state DB for the in-process Codex server, and local file workspace visibility improvements. |
| Codex | AI-assisted commits for local model search/download and tool loop primitives, llama XCFramework CI, Rust/iOS cache and BuildKit asset CI, local file browser and runtime UX, local Codex readiness gating, goal slash command support, BuildKit diagnostics and IPA verification, BuildKit packaging/embedding, manifest encoding, ZIP extraction hardening, xcodebuild/Swift flag compatibility, framework install-name normalization, fakefs diagnostics, compiler dylib handling, signed driver/library preference, and BuildKit risk coverage. |

## Third-Party Project Credits

| Project | Role in Litter |
|---|---|
| OpenAI Codex (`openai/codex`) | Upstream Codex agent/runtime source used through the `shared/third_party/codex` submodule and local patches. |
| ProjectNyxian / Nyxian | Source import used for the on-device Swift BuildKit path. |
| ProjectNyxian / LLVM-On-iOS | Source import and build tooling used for iOS compiler/BuildKit asset work. |

## Notes

Names are normalized where contributors used multiple Git author names or email
addresses. This document is a credit record, not a copyright assignment,
contributor license agreement, or legal opinion.
