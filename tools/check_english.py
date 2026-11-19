#!/usr/bin/env python3
"""Fail when non-English text appears outside the allowed translation files.

Cyrillic and CJK are allowed only in ``LICENSE`` (legal text). Everything else
in the repository -- code, comments, docs, QML/Lua/shell scripts and
configuration -- must be English.
"""

import re
import subprocess
import sys
from pathlib import Path

CYRILLIC = re.compile(r"[\u0400-\u04FF]")
CJK = re.compile(r"[\u4E00-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]")

ALLOWED_CYRILLIC = {"LICENSE"}
ALLOWED_CJK = {"LICENSE"}


def main() -> int:
    tracked = subprocess.check_output(["git", "ls-files", "-z"]).decode("utf-8").split("\0")
    problems = []
    for name in tracked:
        if not name:
            continue
        path = Path(name)
        if not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            if CJK.search(line) and name not in ALLOWED_CJK:
                problems.append(f"{name}:{lineno}: CJK text")
            if CYRILLIC.search(line) and name not in ALLOWED_CYRILLIC:
                problems.append(f"{name}:{lineno}: Cyrillic text")

    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)
    print("English-only text check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
