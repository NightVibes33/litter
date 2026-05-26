# Emotional Mangling Proxy

_What Apple and I both share after this is done_

[![Build em_proxy](https://github.com/SideStore/em_proxy/actions/workflows/build.yml/badge.svg)](https://github.com/SideStore/em_proxy/actions/workflows/build.yml)

## What is EMP

A transparent interface level proxy for TCP packets. This project is designed to work around the loopback limitations on iOS.

## How does it work

By modifying packets and retransmitting them back through a WireGuard tunnel

## How to build

```sh
cargo build --target aarch64-apple-ios
```

## Publishing new release

We use a github action to generate a `.xcframework` for use in Swift PM or XCode.

This overwrites the last build on the tag `Build`.

Either push a commit with `[build]` as the prefix for the commit message or push an empty commit with:

```sh
git commit --allow-empty -m "[build]"
```

## Progress

![Alt](https://repobeats.axiom.co/api/embed/bb97132e96fd2c4caac60aa1441ae55b6382afec.svg "Repobeats analytics image")
