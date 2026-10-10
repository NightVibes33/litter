Legacy SideStore build dependencies still use atty's small public API. This
root-owned adapter delegates detection to maintained is-terminal rather than
retaining the vulnerable Windows implementation in atty 0.2.14
(GHSA-g98v-hv3f-hcfr / RUSTSEC-2021-0145).

The package version preserves dependency compatibility; its implementation is
new and contains no raw pointer access. Keep both SideStore Cargo patches in
sync. Validate consumers on macOS and Windows when changing this adapter.
