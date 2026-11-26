"""Module entry point for `python3 -m groundhog`."""

from __future__ import annotations

import sys

from groundhog.cli import main

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
