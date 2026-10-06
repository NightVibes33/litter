# iOS crash diagnostics

Alley Cãt writes redacted session logs into Documents/Diagnostics. Files → Browse → On My iPhone → Alley Cãt → Diagnostics exposes this directory using the existing UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace settings. CODEX_HOME and account credentials remain in Application Support, outside the shared Documents directory.

Each launch begins a new session log. Info, warning and error entries are written synchronously without a userspace log buffer, so the last completed write survives a process crash. Debug/trace entries stay in memory and OSLog to avoid streaming log volume. Logs rotate at 512 KiB and retain five files. Each entry is bounded and token-redacted before writing. A turn-start entry records the selected model, reasoning effort and whether the runtime is local; it does not include the prompt.

Settings → Diagnostics → Collect Recovery Bundle saves a redacted text bundle directly in this directory. Share Bundle shares that saved file. Five text bundles and five JSON reports are retained independently of the session logs.

Apple MetricKit diagnostic payloads are saved as apple-diagnostic-*.json, including native crash call stacks when provided. Identical payloads are deduplicated. iOS delivers these asynchronously; they may be available on a later launch rather than immediately. Jetsam, force-quitting and other OS terminations may not produce a MetricKit crash report. This logger does not intercept signals or claim to catch every fatal condition.

After reproducing a crash, reopen the app and share the preceding session log and any Apple diagnostic JSON from Files. If no Apple report appears, Settings → Privacy & Security → Analytics & Improvements → Analytics Data may contain a Litter/Alley Cãt .ips or JetsamEvent report. Share that report for a symbolicated native diagnosis. Native execution, Files visibility and MetricKit delivery require device verification; source checks alone do not establish the crash cause.
