# Keyring native backend selection

Source: crates.io keyring 3.6.3. MIT and Apache-2.0 licenses are retained.

Alley Cat's Linux calls are synchronous and use the existing persistent
Linux-keyutils/Secret-Service backend through maintained dbus-secret-service.
The unused async Secret Service backend and its optional zbus 4 dependencies
are removed from the package manifest. Selecting the unsupported async backend
fails compilation explicitly rather than falling back to an insecure store.

Apple Keychain, Windows Credential Manager, Linux persistent storage, mock
credentials, service/account attributes, and the public Entry API are preserved.
No plaintext fallback or advisory-ignore rule is added. The root-owned Codex
patch switches both credential callers to the supported synchronous backend and
adapts native error classification to typed D-Bus errors.

Original crates.io archive SHA-256: `eebcc3aff044e5944a8fbaf69eb277d11986064cba30c468730e8b9909fb551c`.
