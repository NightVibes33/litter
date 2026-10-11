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
no matches in the resulting 57 unique resolved commits. Feather uses a local
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

Reproduce the Swift commit inventory (including explicit local-source review):

```sh
python tools/scripts/audit-swift-dependencies.py --output /tmp/swift-security.json
```

Run `npm audit --package-lock-only --ignore-scripts` in tools/scripts, the
QuickJS documentation directory, and each Cloudflare service to reproduce
the npm inventories.

Feather's Zsign OpenSSL binary dependency moves from package 3.3.3001 to
3.6.5000 (bundled OpenSSL 3.6.5). Wrapper-repository commit scans do not establish
the security status of bundled native binaries; their release provenance and
upstream security notices require separate review. The dependency is pinned
exactly and Feather's actual package resolution is validated in CI.

The mobile and standalone minimuxer OpenSSL source bundles also upgrade to
LTS 3.5.9. The original openssl-src build API is retained with a root-owned
source package; Cargo extracts the immutable upstream archive into OUT_DIR,
verifies its published SHA-256, and performs no build-time network download.
A compatibility test checks the actual linked OpenSSL release. The inventory
now additionally rejects bundles below the reviewed native release baselines
(3.5.9, 3.6.5, or 4.0.3). These checks are distinct from OSV crate advisories.
See shared/rust-bridge/vendor/openssl-src-300.5.9/LITTER_PATCHES.md for provenance and licenses.

Feather's lockfiles are synchronized from a successful Xcode resolution. The
Swift graph compiles and initializes successfully on macOS. Its Zip boundary
test exposed macOS's treatment of nonexistent leaf paths: validation now
resolves and checks each parent component before the leaf is appended.

The unsigned archive's missing Nyxian recovery types are exposed through the
embedded umbrella header. CoreCompiler enum Codable conformances use a
root-owned integration file importing their owning framework, rather than
compiling the upstream file without that module import. The upstream source
gitlink is unchanged. Full unsigned archive validation remains required.

## Post-merge iOS compile repair

The full unsigned build exposed a target-specific compatibility failure in
num_threads 0.1.7 with libc 0.2.190: libc now limits its deprecated Mach task
helper to macOS. A licensed, root-owned num_threads snapshot binds the same
libSystem task-port variable directly. Thread enumeration and cleanup remain
unchanged; libc is not downgraded. The iOS-target crate check passed locally and
now runs in Rust CI. Full unsigned archive validation remains required.

The separate main release failure is npm E404 publishing kittylitter 0.3.13;
its trusted publisher must authorize this fork and release workflow. Pages
continues to use the legacy repository-root upload. The minimal static-site
workflow exists, but changing Pages to workflow mode returns HTTP 403 to the
current connection. Manually dispatching that minimal-site workflow succeeded
and deployed the support site; the legacy source setting still needs to change
to prevent future repository-root uploads. Administrative failures are not
suppressed.

## Rustix and legacy Pages follow-up

Both the next unsigned build and TestFlight asset preparation exposed the same
rustix 1.1.4/libc 0.2.190 Apple constant mismatch. The mobile lockfile upgrades
to upstream rustix 1.1.5, which correctly gates the macOS-only APIs. A standalone
Apple ABI checker compiles every rustix 1.x API plus the actual iOS legacy
rustix, Nix, and num_threads feature paths; its pins must match the iOS metadata
graph. Local iOS compilation passed. Full archive validation remains required.

The legacy Pages job ignored source exclusions because the root .nojekyll flag
forced an entire-repository static upload. Removing that root flag lets the
existing Jekyll exclusions apply; docs is also excluded so the published root
content consists of the static support pages rather than source/vendor trees.
The minimal workflow retains its own generated .nojekyll artifact. The next
legacy build must verify this repair independently of the prior successful
minimal workflow deployment. No repository settings permissions are bypassed.

### Darwin network interface ABI follow-up

The e05def1 unsigned and TestFlight runs reached netdev 0.45.0 and failed
because libc 0.2.190 exposes in6_ifreq only on macOS. The local licensed
netdev source preserves the iOS IPv6 ioctl with XNU's request layout and a
compile-time 288-byte buffer assertion. macOS continues using libc's type.
The standalone Apple ABI checker now includes netdev and checks its pin
against the active mobile dependency graph. Full SDK builds remain required.

### Darwin routing monitor follow-up

Both cea32f39 iOS lanes reached netwatch 0.19.1 and failed because libc 0.2.190
limits routing constants to macOS. The local licensed netwatch source restores
only the XNU constants used by its existing iOS routing parser and monitor.
The production-lockfile iOS check and standalone iOS/macOS checks pass. Both
iOS lanes now check the complete Rust graph with the SDK and V8 assets before
static-library compilation. See IOS_RUNNER_REVIEW.md for the downstream review
and the remaining real archive, packaging, upload and device validation gates.
