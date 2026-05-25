# Authors and Contributors

This file records project attribution for the public Litter fork. It is based on accepted Git commit history and known vendored upstreams, not on GitHub profile speculation. If a name is missing or should be normalized differently, open a focused PR with the commit or upstream reference.

## Original Project

- Daniel Nakov / dnakov - original creator and upstream maintainer of `dnakov/litter`.

## Current Fork

- NightVibes33 / NightVibes3 / ZYN / Zyn - current fork maintainer and developer for `NightVibes33/litter`. These names refer to the same maintainer identity in this fork.
- Codex / OpenAI-assisted implementation - AI-assisted commits made under maintainer direction in this fork. These entries are attribution notes, not a replacement for human copyright ownership.

## Accepted Upstream Contributors

The following people appear as accepted authors in `dnakov/litter` on `upstream/main` as fetched on 2026-05-17. Duplicate local email identities were normalized where the history clearly used the same public name.

- Daniel Nakov / dnakov
- sigkitten
- Kaynan Sampaio de Camargo / kaynan
- Maky
- kkellyoffical
- Coy Geek
- D-DRUMROLL
- Benjamin Western
- Jason Penilla
- Thomas Zarebczan
- frixa
- ryanchen01
- shuv
- sliced-paraiba
- zulfaza

Upstream commit trailers also include AI-assisted co-author entries for Claude Sonnet 4.6. They are recorded here as tool attribution only, not as a human contributor account.

## Vendored and Referenced Upstreams

Litter also includes or builds against third-party projects. Their copyright and license notices remain with those upstream projects. See `THIRD_PARTY_NOTICES.md` and the license files in each vendored path.

- OpenAI Codex source under `shared/third_party/codex`.
- ProjectNyxian/Nyxian and emexDE-derived BuildKit source under `ThirdParty/Nyxian`.
- ProjectNyxian/LLVM-On-iOS compiler support references.
- SideStore Team and contributors for the SideStore sideloading workflow, Anisette server list convention, update-source expectations, and LocalDevVPN-based install/refresh model Litter documents and targets.
- AltStore / Riley Testut and contributors for the original AltStore app/source/signing model that SideStore builds on.
- Coxson Engineering LLC / jkcoxson for LocalDevVPN and related on-device sideloading infrastructure including minimuxer and em_proxy.
- osy / Jitterbug contributors for the loopback/debugging approach referenced by SideStore's LocalDevVPN flow.
- dnakov/litter-ish for the embedded iSH backend.
- dnakov/alleycat bridge crates used by the Rust mobile bridge.
- ZIPFoundation, Rust crates, Swift packages, and other package-manager dependencies resolved by the build system.

## License Note

Litter is open source under GPLv3 with an additional GPLv3 section 7 store-distribution permission. It is not MIT licensed. Vendored Nyxian/emexDE code is AGPL-3.0-or-later, OpenAI Codex code is Apache-2.0, and other third-party dependencies retain their own licenses.
