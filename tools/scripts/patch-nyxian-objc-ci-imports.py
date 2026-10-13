#!/usr/bin/env python3
"""Patch missing Nyxian Objective-C imports required by the Xcode CI target."""

from pathlib import Path

SOURCE = Path("ThirdParty/EmexDE/Source/Nyxian/LindChain/ProcEnvironment/PEUserspaceManager.m")
REQUIRED_IMPORTS = (
    "#import <LindChain/IDEFoundation/NXAlertDiagnosticPresenter.h>",
    "#import <LindChain/ProcEnvironment/Utils/misc.h>",
)
ANCHOR = "#import <Nyxian-Swift.h>"


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


if __name__ == "__main__":
    main()
