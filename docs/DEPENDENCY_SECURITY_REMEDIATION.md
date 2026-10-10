# Dependency security remediation

PR #16 follows PR #15's compatible dependency upgrades. GitHub last reported
32 default-branch alerts after PR #15, down from 36. The private Dependabot
endpoint still returns HTTP 403 to the repository connection. Registry scanner
findings are a separate inventory and cannot establish that those alerts closed.

## Changes

The mobile graph upgrades AWS JSON, Faster Hex, Gitoxide, Hickory, JWT, LRU,
OpenSSL, OpenTelemetry, Pageant, Plist/Quick XML, Russh, Serde With, and Tar.
Root-owned Codex patches retain the upstream gitlink. Rama DNS preserves its
providers and record types while migrating to matching Hickory 0.26 packages.
OpenTelemetry HTTP retains its Reqwest 0.13 implementation and adds Reqwest 0.12
support for existing application clients, preserving TLS identity and policy.

Both SideStore native graphs upgrade TLS/certificate validation, random numbers,
archive parsing, and applicable HTTP dependencies. Minimuxer also upgrades Bytes,
H2, OpenSSL, Quinn, Time, and ZIP. The atty adapter replaces unsafe legacy terminal
detection with maintained is-terminal.

Maintenance replacements retain pinned caller APIs through small root-owned
adapters: ansi_term uses nu-ansi-term; json uses jzon; fxhash uses ccl-fxhash;
paste uses pastey; atomic-polyfill uses portable-atomic. i18n-embed-fl imports
maintained proc-macro-error3 directly. Starlark and its syntax crate use
maintained derive_more Debug and standard Clone, preserving omitted debug fields.
Their sources and sibling dependencies remain pinned to the previous Starlark
Git revision. These are implementation replacements, not patched releases of
legacy packages. Standalone vendor lockfiles receive the same replacements.

## RSA backend migration

JWT uses AWS-LC. The pinned Russh/SSH Key source adapters also use AWS-LC for RSA
key validation, generation, PKCS#1/PKCS#8 import/export, and SHA-256/SHA-512
signatures. OpenSSH key components and fingerprints retain their formats.
OpenSSH does not store the two CRT exponents; their conversion uses maintained
crypto-bigint's constant-time remainder and zeroized temporary storage. AWS-LC
validates the imported key. No affected RustCrypto rsa package remains resolved.

Compatibility limits: AWS-LC requires RSA private keys of at least 2048 bits.
SHA-1 private-key authentication signing is rejected; clients must use RSA SHA-2,
Ed25519, or ECDSA. Legacy SHA-1 host-signature verification remains available with
2048-bit or larger keys. The backend patches are root-owned changes requiring
source review and installed-device acceptance, not upstream fixed releases.

RustBridge still selects only its used services, including remote pairing, TSS
image mounting, and TCP tunnels, without unused classic RSA generation. The
standalone idevice optional classic-pairing path also removes RustCrypto RSA:
OpenSSL generates and signs certificates while preserving SHA-256, PKCS#8,
serial number, validity, and root extensions. Its ca module is private.

## Validation and inventory

Local compatibility tests cover legacy ANSI names/escapes, JSON Unicode and
invalid input, fixed hash behavior, token-pasting macros, atomic operations,
RSA SHA-2 signing and negative verification, an independent OpenSSH signature
fixture, and OpenSSH/PKCS#8 identity round trips. Pairing certificate tests verify
both certificates with the host key and check device key identity and PKCS#8.
Mobile all-target and both native library compilation are required CI checks.
The macOS native workflow additionally tests optional certificate generation.

Reproduce the tracked-lockfile registry inventory:

```sh
python tools/scripts/audit-rust-dependencies.py --output /tmp/rust-security.json
```

The latest candidate inventory reports zero registry package/version advisories
across all nine tracked Cargo lockfiles. The report also explicitly lists local
and Git packages requiring source review. A registry scan cannot validate a
source replacement or establish constant-time behavior by itself. No advisory
ignore list or alert dismissal is used.

CI and installed-device network, SSH, pairing, and signing acceptance remain
necessary before release. Recheck the actual GitHub Dependabot count after merge.

## Swift and npm dependency remediation

All six tracked Swift package resolutions and both npm lockfiles were checked.
Feather upgrades Vapor to 4.122.2, Swift Crypto to 4.5.2, SwiftNIO to 2.101.0,
NIO HTTP/2 to 1.45.0, and NIO SSL to 2.37.2. A commit-based OSV scan reports
no matches in the resulting 62 unique resolved commits. Feather uses a local
Zip 2.1.2 source patch because upstream has no fixed release for CVE-2023-39135.
Extraction destinations are validated before directory creation or file writes,
including existing symlink resolution. This source replacement requires review;
removing its remote pin does not mean upstream Zip 2.1.2 is safe. Tests cover
normal destinations and invalid boundary names without crafting attack archives.

QuickJS documentation upgrades Docusaurus to 3.10.2 and maintained transitive
dependencies. Unpatched Braces is replaced by a local source implementation
with bounded input and iterative AST validation before recursive work. Its
ordinary API compatibility tests pass. This patch requires source review too.
Both npm lockfile audits report zero findings; the documentation production
build and its two compatibility tests pass locally. No audit omission, ignore
list, or alert dismissal is used.

The macOS workflow compiles and initializes the fixed Swift graph and runs Zip
tests before building native iOS libraries. The documentation job installs the
lockfile, audits both npm graphs, tests compatibility, and builds the site.
These checks do not replace a full Feather app build or device acceptance.
GitHub's private Dependabot endpoint remains inaccessible: independent inventory
counts must not be presented as GitHub's remaining alert count.

The Cloudflare signup and push-proxy services now have reproducible npm locks.
Workers types move to major 5 to satisfy Wrangler's current peer requirement.
Both full dependency audits report zero findings; CI also checks TypeScript
with the installed graph. This is a build dependency compatibility update.
