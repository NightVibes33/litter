#!/usr/bin/env python3
"""Patch missing Nyxian Objective-C imports required by the Xcode CI target."""

from pathlib import Path
import re

SOURCE = Path("ThirdParty/EmexDE/Source/Nyxian/LindChain/ProcEnvironment/PEUserspaceManager.m")
REQUIRED_IMPORTS = (
    "#import <LindChain/IDEFoundation/NXAlertDiagnosticPresenter.h>",
    "#import <LindChain/ProcEnvironment/Utils/misc.h>",
)
ANCHOR = "#import <Nyxian-Swift.h>"
SHIMS = SOURCE.parent / "Shims"
SYSCALL_CONSUMERS = ("posix_spawn.m", "vfork.m", "environment.m", "application.m")


def patch_liveshim_module_import(text: str) -> str:
    """Import the whole module, including declarations hidden by a prior submodule import."""
    header = re.compile(r"^#(?:import|include) <LiveShim/LiveShimSyscall\.h>$", re.MULTILINE)
    if re.search(r"^@import LiveShim;$", text, re.MULTILINE):
        return text
    if len(header.findall(text)) != 1:
        raise ValueError("expected exactly one LiveShim syscall header import")
    return header.sub("@import LiveShim;", text, count=1)


def main() -> None:
    text = SOURCE.read_text(encoding="utf-8")
    missing = [line for line in REQUIRED_IMPORTS if line not in text]
    if missing:
        if ANCHOR not in text:
            raise SystemExit(f"missing import anchor in {SOURCE}")
        text = text.replace(ANCHOR, "\n".join((*missing, ANCHOR)), 1)
        SOURCE.write_text(text, encoding="utf-8")
    for line in REQUIRED_IMPORTS:
        if line not in text:
            raise SystemExit(f"failed to install required import: {line}")
    print(f"Nyxian Objective-C imports ready: {SOURCE}")
    for name in SYSCALL_CONSUMERS:
        source = SHIMS / name
        text = source.read_text(encoding="utf-8")
        try:
            patched = patch_liveshim_module_import(text)
        except ValueError as error:
            raise SystemExit(f"Cannot patch {source}: {error}") from error
        if patched != text:
            source.write_text(patched, encoding="utf-8")
        print(f"Nyxian LiveShim module import ready: {source}")


if __name__ == "__main__":
    main()
