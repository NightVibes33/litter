#!/usr/bin/env python3
"""Add declaration-only Swift compatibility to the bundled LLVM 19 headers."""
from pathlib import Path
import sys


def patch_headers(root: Path) -> None:
    compiler = root / 'llvm/Support/Compiler.h'
    text = compiler.read_text()
    if '#define LLVM_ABI ' not in text:
        text += '\n// Swift compiler header overlay uses the newer visibility spelling.\n#ifndef LLVM_ABI\n#define LLVM_ABI LLVM_EXTERNAL_VISIBILITY\n#endif\n'
        compiler.write_text(text)

    target = root / 'llvm/MC/MCTargetOptions.h'
    text = target.read_text()
    if 'enum class CASBackendMode' not in text:
        # Add only the enum used by Swift IRGenOptions. Replacing this whole
        # header would change the MCTargetOptions layout expected by llvm.a.
        text += '\n#ifndef LITTER_LLVM_CAS_BACKEND_MODE\n#define LITTER_LLVM_CAS_BACKEND_MODE\nnamespace llvm {\nenum class CASBackendMode { Native, CASID, Verify };\n}\n#endif\n'
        target.write_text(text)

    irgen = root / 'swift/AST/IRGenOptions.h'
    if irgen.exists():
        text = irgen.read_text()
        include = '#include "llvm/MC/MCTargetOptions.h"'
        if include not in text:
            anchor = '#include "llvm/Support/raw_ostream.h"'
            if anchor not in text:
                raise ValueError('Unexpected Swift IRGenOptions include layout')
            irgen.write_text(text.replace(anchor, anchor + '\n' + include, 1))


if __name__ == '__main__':
    patch_headers(Path(sys.argv[1]))
