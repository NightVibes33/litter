# Borrowed string deserialization

Source: crates.io toml 0.9.12+spec-1.1.0, retaining MIT and Apache-2.0 licenses.
Archive SHA-256: `cf92845e79fc2e2def6a5d828f0801e29a2f8acc037becc5ab08595c7d5e9863`.

The parser already represents unchanged input strings as DeString::Borrowed
with the input lifetime. The serde adapter now forwards those to
Visitor::visit_borrowed_str instead of visit_str. Owned decoded strings keep
the existing visit_string path. This restores basic-toml's borrowed config
contract for Askama's template directory and syntax configuration without
leaks, unsafe lifetime casts, or reinstating an unmaintained parser.

Validation requires borrowed config regression tests and actual UniFFI Swift
and Kotlin binding generation, in addition to ordinary owned TOML parsing.
