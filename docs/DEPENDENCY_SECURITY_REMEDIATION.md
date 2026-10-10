# Dependency security remediation

This change follows the initial compatible dependency patch in PR #15. It does
not claim to match or close every private GitHub Dependabot alert: that endpoint
currently returns HTTP 403 to the repository connection. GitHub last reported
36 alerts on the default branch. OSV package/version findings are a different
inventory and must not be presented as GitHub alert counts.

## Changes

The mobile lockfile upgrades AWS JSON parsing, Faster Hex, Gitoxide, Hickory,
JWT validation, LRU, OpenSSL, OpenTelemetry, Pageant, Plist/Quick XML, Russh,
Serde With, and Tar. The Codex manifest and telemetry compatibility changes are
root-owned patches applied by `sync-codex.sh`; the upstream gitlink is unchanged.

Rama DNS is adapted to Hickory 0.26 with matching resolver, protocol, and network
packages. DNS provider choices and record types are preserved. OpenTelemetry
HTTP retains its upstream Reqwest 0.13 support and adds an adapter for existing
Reqwest 0.12 clients, preserving the application's TLS and network policy path.

Both SideStore native libraries upgrade TLS, certificate validation, random
number generation, archive parsing, and applicable HTTP dependencies. Minimuxer
also upgrades Bytes, H2, OpenSSL, Quinn, Time, and its yanked ZIP dependency.
Legacy atty consumers use a root-owned compatibility adapter backed by maintained
is-terminal; the vulnerable Windows raw-pointer implementation is removed from
their dependency graph. This is a source replacement, not an upstream atty fix.

The macOS dependency workflow builds both actual iOS static libraries with
locked resolution. The mobile workflow compiles all targets and runs existing
mobile client and Slingshot tests. Local/path adapters also require source review;
a registry-version scanner alone cannot assess them.

## Remaining findings

- RSA: `RUSTSEC-2023-0071` reports no patched release. It remains in SSH and
  device-pairing dependency paths. Upgrading to another affected RSA release or
  hiding the advisory does not fix it; a cryptographic backend migration needs
  separate compatibility and timing-safety validation.
- Maintenance advisories remain for legacy dependencies including ANSI Term,
  Atomic Polyfill, Derivative, Fxhash, Json, Paste, and Proc Macro Error 2. They
  require maintained parent-library replacements or reviewed compatibility
  patches. They are not suppressed here.
- Standalone vendored-library lockfiles are scanned too, even though production
  uses the root mobile lockfile. Their optional telemetry/DNS test graphs need
  additional coordinated upgrades; they are retained rather than deleted to
  hide findings.

Reproduce the complete tracked-lockfile registry inventory with:

```sh
python tools/scripts/audit-rust-dependencies.py --output /tmp/rust-security.json
```

The result includes every tracked Cargo lockfile, not just production packages.
Network, SSH, device pairing, and signing still need acceptance on installed
devices after these dependency changes. Passing compilation is not that acceptance.
