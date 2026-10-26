# AWS Config P-256 migration

Source: crates.io `aws-config` 1.8.14, retaining its Apache-2.0 license and
authentication flows. The only runtime change is DPoP's P-256 dependency:
0.13.2 → maintained 0.14.0, resolving the legacy crypto-bigint 0.5 dependency.
The maintained 0.7 crypto-bigint release is pinned by the workspace lockfile.

DPoP still uses randomized ES256 signatures and the same SEC1 PEM key and
public-coordinate formats. Randomness now comes directly from getrandom's
system CSPRNG via the current fallible signing API; failures are returned as
login errors. No account provider, login mode, or secure credential store is
removed. The inherited DPoP tests and independent signature verification are
required validation.

Original crates.io archive SHA-256: `8a8fc176d53d6fe85017f230405e3255cedb4a02221cb55ed6d76dccbbb099b2`.
