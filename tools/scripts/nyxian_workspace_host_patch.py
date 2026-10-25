"""Select the authentic Nyxian workspace implementation by build target.

Both the embedded emexDE host framework and the separate LiveProcess extension
compile the *same* upstream LDEApplicationWorkspace.m. The presence of a
Swift-generated header is not a valid compile-time host/extension discriminator.
The emexDE target defines HOST_ENV=1, while LiveProcess does not.
"""

OLD_BRANCH = "#if __has_include(<Nyxian-Swift.h>)\n#define LIVEPROCESS 0"
HOST_BRANCH = "#if HOST_ENV\n#define LIVEPROCESS 0"
LIVEPROCESS_BRANCH = "#define LIVEPROCESS 1"
OLD_ENDIF = "#endif /* __has_include(<Nyxian-Swift.h>) */"
HOST_ENDIF = "#endif /* HOST_ENV */"


def patch_workspace_host_selector(source: str) -> str:
    """Return the source with correct host selection or fail on upstream drift."""
    if LIVEPROCESS_BRANCH not in source:
        raise ValueError("missing real LiveProcess branch in upstream source")

    if OLD_BRANCH in source:
        if source.count(OLD_BRANCH) != 1 or source.count(OLD_ENDIF) != 1:
            raise ValueError("ambiguous upstream header-based host selection")
        source = source.replace(OLD_BRANCH, HOST_BRANCH, 1)
        source = source.replace(OLD_ENDIF, HOST_ENDIF, 1)
    elif HOST_BRANCH not in source:
        raise ValueError("no recognized host selection in upstream source")

    if source.count(HOST_BRANCH) != 1 or source.count(HOST_ENDIF) != 1:
        raise ValueError("incomplete host selection conversion")
    return source
