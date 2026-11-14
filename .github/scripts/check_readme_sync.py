#!/usr/bin/env python3
"""Check that the README and the module manifest agree on the version.

The README is what the registry shows to a user, and the install line in it
is the first thing a reader copies. If the README names a version the
manifest does not have, `moon add` in that line resolves to a release that
does not exist -- or, worse, to an OLD one, while the registry page advertises
the new one.

The check therefore does two things:

1. it reads the version out of ``moon.mod``,
2. it scans the README for every ``LunaFlow@<version>`` reference and requires
   all of them to be that version.

Only LunaFlow's OWN coordinates are checked. The README also names other
modules -- ``riantr/moonbit_doubleML@latest`` resolves to 0.164.62 in the
committed report table -- and those versions are not this release's business.

(The module itself has no pinned dependency any more: the async runtime comes
from the toolchain-bundled ``moonbitlang/core``, so there is no dependency
version to keep in step with.)

It exits 1 and prints the offending lines when they disagree.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "moon.mod"
README = ROOT / "README.md"

# `riantr/LunaFlow@0.1.0`, `LunaFlow@0.1.0`, `mooncakes.io/docs/riantr/LunaFlow@0.1.0`
VERSION_PATTERN = re.compile(r"LunaFlow@(\d+\.\d+\.\d+)")


def manifest_version() -> str:
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("version"):
            _, _, value = stripped.partition("=")
            return value.strip().strip('"')
    raise SystemExit(f"no version field in {MANIFEST}")


def readme_versions(text: str) -> list[tuple[int, str, str]]:
    """Every LunaFlow version reference in the README, with its line number.

    THE RELEASE HISTORY IS EXEMPT. A block headed
    ``### What changed in <version>`` is about THAT version by construction:
    it quotes what that version printed and what it changed, so a coordinate
    in it is a quotation, not an install line. The 0.1.14 section quotes
    ``riantr/LunaFlow@0.1.14`` -- the title that version printed -- and a
    reader copying an install line copies one from the Install section, not
    one out of a changelog table.

    Every other section is checked in full: the Install section, the Quick
    Start, the CLI reference and the registry link are all live, copyable
    coordinates, and the exemption reaches none of them.
    """
    found = []
    in_history = False
    history_level = 0
    for number, line in enumerate(text.splitlines(), start=1):
        heading = re.match(r"^(#{1,6})\s+(.*)$", line)
        if heading:
            level = len(heading.group(1))
            title = heading.group(2)
            if re.match(r"^What changed in \d+\.\d+\.\d+\s*$", title):
                in_history = True
                history_level = level
            elif in_history and level <= history_level:
                in_history = False
        if in_history:
            continue
        for match in VERSION_PATTERN.finditer(line):
            found.append((number, match.group(0), match.group(1)))
    return found


def main() -> int:
    version = manifest_version()
    text = README.read_text(encoding="utf-8")
    mentions = readme_versions(text)

    if not mentions:
        print(f"README does not mention any LunaFlow version; expected v{version}.")
        return 1

    stale = [item for item in mentions if item[2] != version]
    if stale:
        print(f"moon.mod is at {version}, the README disagrees:")
        for number, token, found in stale:
            print(f"  README.md:{number}: {token} (expected {version})")
        return 1

    print(f"moon.mod and README.md agree on {version} ({len(mentions)} reference(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
