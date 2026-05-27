# Contributing

## Project status

Litter is under active development. A lot of the app is still moving: the iOS UI, Rust bridge, embedded iSH fakefs, BuildKit request bridge, signing flow, and release workflows all depend on each other.

Small, focused PRs have the best chance of landing. Broad refactors, drive-by cleanups, and feature piles usually collide with work that is already underway.

## Maintainer identity and attribution

The original upstream project is `dnakov/litter` by Daniel Nakov / dnakov. This public fork is maintained by NightVibes33. In this repo, NightVibes, NightVibes33, NightVibes3, ZYN, and Zyn are the same fork maintainer identity, not separate contributors.

Do not open attribution PRs that split those names into separate people. If author or credit information needs to change, keep it narrow and include the commit history or upstream source that proves the correction.

## Before you open a PR

- **Open an issue first** if you're proposing anything non-trivial. Saves you the work of writing code that overlaps with something we're already doing or have already decided against.
- **Keep it small.** One concern per PR. If you find yourself touching unrelated files, split it.
- **Target a specific problem.** A clear bug, a clear missing piece, a clear regression — not "I think this code could be cleaner."
- **Match the existing style.** Don't reformat code, rename variables, or rearrange things outside the scope of your change.
- **Don't bundle dependency upgrades** with feature/bug PRs.
- **Say how you tested it.** Include the local command, Xcode build, GitHub Actions run, or device check you used.
- **Update the docs** when behavior changes. README updates are required for BuildKit, signing, AltStore/SideStore source, terminal, file browser, runtime, and release-flow changes.
- **Credit upstreams.** If a change uses, vendors, mirrors, or depends on another project, update `THIRD_PARTY_NOTICES.md` and, when appropriate, `AUTHORS.md` with the upstream project, maintainer/team, URL, and license.

## Things that will not be merged

- Large refactors not requested by a maintainer.
- Stylistic-only changes (renames, formatting, comment cleanup).
- New features without prior discussion in an issue.
- PRs that depend on other unmerged PRs.
- Anything that breaks supported iOS workflows without a clear reason.
- Commits that include private certificates, Apple ID credentials, provisioning profiles, API tokens, private BuildKit asset ZIPs, or Apple SDK payloads.

## BuildKit, signing, and sideloading changes

BuildKit work needs extra care because public source, private assets, and the installed IPA are separate pieces.

- Public source can change `ThirdParty/Nyxian`, app UI, shell shims, request handling, and release scripts.
- Installed app behavior only changes for private native driver work after a new `LitterBuildKitAssets.zip` is built, verified, uploaded, and used by the IPA workflow.
- Apple ID login belongs in the app Keychain. Never commit Apple ID credentials or Anisette session data.
- Signing validation must reject bad `.p12` passwords, missing private keys, profile mismatches, untrusted certificates, and revoked certificates.
- SideStore Anisette servers provide Apple authentication metadata. They are not a replacement for LocalDevVPN or the install/refresh transport.
- Full on-device install/refresh should stay blocked unless signing is valid and the LocalDevVPN-style tunnel is available.
- AltStore/SideStore source updates must keep every released IPA version installable through the `versions` history, not only the newest IPA.

If a PR touches this area, say whether it needs a private BuildKit asset rebuild, a new IPA build, both, or neither.

## Setup

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for prerequisites and build commands, and [AGENTS.md](AGENTS.md) for repo conventions.
