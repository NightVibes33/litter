# Nyxian + SideStore upstream integration (staging)

This branch preserves the existing Alley Cat app, native bridges, settings theme,
KittyStore branding, existing signing flow and all custom behavior.

**Sources pinned (2026-10-09)**

- Embedded Nyxian: `emexlab/Nyxian@350dd8dbeb796bc0ff5bc91ef770f1a2994432e7`
  (previous: `8f606193bed2b5a40e1fccfc2f95123730b1bf26`).
- SideStore upstream: `SideStore/SideStore@0dd743f75afc358b0ba4a002feb5f19474492371`.
  The latest source is checked out **alongside** the current embedded vendor tree.
- Current active SideStore vendor: `ThirdParty/SideStore/Source`; its old
  `.litter-upstream-commit` names `8485efe6c2f6f0fc1eb31cddc27c2abb4aa22d10`.
  Git history has diverged from upstream. Replacing this tree outright would
  discard KittyStore-specific signing, minimuxer, resource, and UI adaptations.
- Current BuildKit vendor: `ThirdParty/Nyxian`, older ProjectNyxian layout;
  the upstream `Frameworks/CoreCompiler` layout is incompatible with parts of
  `tools/scripts/build-nyxian-buildkit-assets.sh` without a migration.

**Gate before merging into main**

1. Confirm the two sources and all nested dependency revisions can initialize.
2. Migrate the *active* SideStore build into the new upstream, including
   new SideSign/minimuxer dependencies and Xcode target updates, retaining
   existing KittyStore-specific patches.
3. Reconcile the BuildKit vendor/LiveProcess source and compiler toolchain
   against the new embedded Nyxian revision.
4. Green unsigned iOS IPA + clean in-app Nyxian launch, SideStore source addition,
   Apple ID signing, and extension restart on a device.

The branch is **not a claim that items 2–4 have passed**. See
`ThirdParty/upstream-integration.json` for source provenance and
`tools/scripts/verify-upstream-integration.py` for reproducible checks.
