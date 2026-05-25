Summary

- Added a file/dir mount picker for local iPhone runtime mounts: press and hold the server pill to mount.
- Added Real Time voice API-key fallback when OAuth realtime auth is unavailable.
- Fixed active-turn composer text entry so Send is available while a turn is running.
- Fixed a CarPlay voice crash when reopening or resuming an active voice session.
- Improved Real Time voice error reporting for unexpected session closes.
- Fixed OpenCode/Pi model catalog loading through Alleycat.
- Fixed Pi/alleycat remote project browsing when directory-picker commands were rejected.

What to test

- Local iPhone mounts: connect to the local iPhone runtime, press and hold the server pill, pick a file or directory, and confirm it mounts.
- Real Time auth fallback: configure OAuth and an API key, start voice, and confirm fallback auth can connect.
- Active-turn composer: type while a turn is running, confirm Send appears, then clear text and confirm Cancel returns.
- CarPlay voice: start or resume CarPlay voice and confirm Now Playing opens without crashing.
- Real Time errors: confirm an unexpected session close shows a specific error.
- OpenCode/Pi models: connect to an Alleycat host, open the model picker, and confirm models load.
- Remote project picker: connect to a Pi/alleycat host, open the new-project directory picker, and confirm folders load.
