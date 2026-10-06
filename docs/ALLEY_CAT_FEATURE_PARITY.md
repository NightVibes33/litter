# Alley Cãt feature comparison

Compared current main with pre-integration commit `e8cfc3e0` (PR 13 first parent). This is a source comparison, not a comparison of every historical TestFlight binary. An exact older build number is needed to map a specific installed version.

| Feature | Finding and repair |
| --- | --- |
| Icon switcher | All 13 options, preview assets, alternate icon sets and plist entries survived unchanged. Settings navigation was lost; restored. Existing Pro and LiveContainer rules remain. |
| Terminal | Settings destination survived, but its row disappeared; restored. |
| Updates | Screen survived without an entry point; restored. Its existing distribution checks remain responsible for safe signed versus sideload behavior. |
| Diagnostics | Recovery bundle screen survived without an entry point; restored. |
| Onboarding replay | Screen survived but both replay entry and app-level replay consumer disappeared. Restored as a Settings sheet with working Files, Terminal, Computers, Appearance, Conversation and Harnesses routes. |
| First-run onboarding | Old app-level automatic presentation is absent. Replay restoration does not restore automatic first-run presentation. |
| Wake Pet / experimental controls | Still reachable under Settings → Advanced. |
| Font controls | Moved to Appearance; new defaults are system font and medium size. Existing saved preferences survive. |
| Plugins / Connectors | Old SettingsFeatureVisibility flags were already false; not a newly lost shipping entry. |
| KittyStore / Signing / Nyxian / BuildKit | Still routed with distribution capability checks. |
| AI Providers | Old profile screen remains but AIProviderStore has no consumer in the current conversation runtime. Exposing its saved profiles would not implement routing. Replay now opens live Harness settings instead. |
| GPT 6.1 Sol | Neither pinned Codex catalog nor current fork default catalog advertises it. Model picker uses live server entries without an ID allowlist; refresh is available. No backend access or model metadata is inferred from a display name. Exact connected runtime and its advertised catalog are required to establish why it is absent. |

Native navigation and icon application must be verified in an iOS build/device. No model execution or access is claimed by this comparison.
