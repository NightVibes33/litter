#!/usr/bin/env python3
from __future__ import annotations
import argparse
import pathlib
import subprocess

EXPECTED_CODEX = "be2951ea34f0d295ed0becf97079f92fa5f6950e"
MOBILE = 'any(target_os = "ios", target_os = "android")'
DESKTOP = 'not(any(target_os = "ios", target_os = "android"))'

def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f"error: locked Codex shape changed while patching {label}")
    return text.replace(old, new, 1)

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--codex-root", required=True)
    root = pathlib.Path(ap.parse_args().codex_root).resolve()
    head = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    if head != EXPECTED_CODEX:
        raise SystemExit(f"error: expected Codex {EXPECTED_CODEX}, got {head}")

    ws = root / "codex-rs/Cargo.toml"
    text = ws.read_text()
    if 'rquickjs = { version = "0.9.0"' not in text:
        anchor = 'reqwest = { version = "0.13", default-features = false }\n'
        if anchor not in text:
            anchor = 'serde_json = "1"\n'
        if anchor not in text:
            raise SystemExit("error: no workspace dependency anchor for rquickjs")
        text = text.replace(anchor, anchor + 'rquickjs = { version = "0.9.0", features = ["bindgen", "futures", "parallel"] }\n', 1)
        ws.write_text(text)

    cargo = root / "codex-rs/code-mode/Cargo.toml"
    text = cargo.read_text()
    if 'rquickjs = { workspace = true }' not in text:
        marker = '\n[dev-dependencies]\n'
        if marker not in text:
            raise SystemExit("error: code-mode Cargo.toml shape changed")
        text = text.replace(marker, f'\n[target.\'cfg({MOBILE})\'.dependencies]\nrquickjs = {{ workspace = true }}\n' + marker, 1)
        cargo.write_text(text)

    lib = root / "codex-rs/code-mode/src/lib.rs"
    old = """mod grpc_session;
mod remote_session;

pub use codex_code_mode_protocol::*;
pub use grpc_session::GrpcCodeModeSessionProvider;
pub use remote_session::DisabledCodeModeSessionProvider;
pub use remote_session::ProcessOwnedCodeModeSession;
pub use remote_session::ProcessOwnedCodeModeSessionProvider;
"""
    new = f"""mod grpc_session;
#[cfg({DESKTOP})]
mod remote_session;
#[cfg({MOBILE})]
mod service_mobile;

pub use codex_code_mode_protocol::*;
pub use grpc_session::GrpcCodeModeSessionProvider;
#[cfg({DESKTOP})]
pub use remote_session::DisabledCodeModeSessionProvider;
#[cfg({DESKTOP})]
pub use remote_session::ProcessOwnedCodeModeSession;
#[cfg({DESKTOP})]
pub use remote_session::ProcessOwnedCodeModeSessionProvider;
#[cfg({MOBILE})]
pub use service_mobile::DisabledCodeModeSessionProvider;
#[cfg({MOBILE})]
pub use service_mobile::InProcessCodeModeSession;
#[cfg({MOBILE})]
pub use service_mobile::InProcessCodeModeSessionProvider;
#[cfg({MOBILE})]
pub use service_mobile::ProcessOwnedCodeModeSession;
#[cfg({MOBILE})]
pub use service_mobile::ProcessOwnedCodeModeSessionProvider;
"""
    text = lib.read_text()
    if text != new:
        if text != old:
            raise SystemExit("error: code-mode lib.rs shape changed")
        lib.write_text(new)

    template = pathlib.Path(__file__).resolve().parents[2] / "patches/codex/mobile-code-mode/service_mobile.rs"
    service = root / "codex-rs/code-mode/src/service_mobile.rs"
    desired = template.read_text()
    if not desired.endswith("\n"):
        desired += "\n"
    if not service.exists() or service.read_text() != desired:
        service.write_text(desired)

    manager = root / "codex-rs/core/src/thread_manager.rs"
    old = """        let code_mode_session_provider: Arc<dyn CodeModeSessionProvider> =
            if config.features.enabled(Feature::CodeModeHost)
                || config.code_mode.disable_in_process_fallback
            {
                Arc::new(ProcessOwnedCodeModeSessionProvider::default())
            } else {
                Arc::new(DisabledCodeModeSessionProvider)
            };
"""
    new = f"""        #[cfg({MOBILE})]
        let code_mode_session_provider: Arc<dyn CodeModeSessionProvider> =
            Arc::new(ProcessOwnedCodeModeSessionProvider::default());
        #[cfg({DESKTOP})]
        let code_mode_session_provider: Arc<dyn CodeModeSessionProvider> =
            if config.features.enabled(Feature::CodeModeHost)
                || config.code_mode.disable_in_process_fallback
            {{
                Arc::new(ProcessOwnedCodeModeSessionProvider::default())
            }} else {{
                Arc::new(DisabledCodeModeSessionProvider)
            }};
"""
    text = replace_once(manager.read_text(), old, new, "ThreadManager code-mode provider")
    manager.write_text(text)

    requirements = {
        service: ["globalThis.tools = Object.create(null);", "globalThis.ALL_TOOLS = ", "delegate.invoke_tool", "code_mode_host_duration: None"],
        cargo: ['rquickjs = { workspace = true }'],
        ws: ['rquickjs = { version = "0.9.0"'],
        lib: ["mod service_mobile;", "pub use service_mobile::ProcessOwnedCodeModeSessionProvider;"],
        manager: ['cfg(any(target_os = "ios", target_os = "android"))', "ProcessOwnedCodeModeSessionProvider::default()"],
    }
    for path, needles in requirements.items():
        body = path.read_text()
        for needle in needles:
            if needle not in body:
                raise SystemExit(f"error: {path.relative_to(root)} missing {needle}")
    forbidden = ["code mode is unavailable on mobile", "exec is unavailable on mobile targets", "MOBILE_UNSUPPORTED_MESSAGE"]
    body = service.read_text()
    for needle in forbidden:
        if needle in body:
            raise SystemExit(f"error: unsupported mobile code-mode stub marker: {needle}")
    print("Mobile Codex code mode verified: upstream protocol + QuickJS + nested host tools")

if __name__ == "__main__":
    main()
