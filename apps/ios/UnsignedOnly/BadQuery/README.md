# Unsigned bad_query integration

Pinned implementation: `forcequitOS/bad_query` commit `73ef6da1adabef0982fd00e36cb85f21b8f8194a`.

This directory is outside `Sources/Litter` and is not part of the normal/TestFlight XcodeGen source graph. `tools/scripts/patch-ios-fast-device-project.py` adds it only to fast/release unsigned device builds, patches the Apple on-device agent with `readDeviceFile`, `listDeviceDirectory`, and `writeDeviceFile`, and temporarily imports `bad_query.h` into the unsigned build's bridging header.
