"""CLI: ``python -m zero_core_runtime install [--backend=sqlite|postgres]``."""

from __future__ import annotations

import argparse
import sys

from . import _native

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="zero_core_runtime")
    sub = p.add_subparsers(dest="command", required=True)
    install = sub.add_parser("install", help="Pre-fetch libzero into the user cache")
    install.add_argument(
        "--backend",
        choices=["sqlite", "postgres"],
        default="sqlite",
        help="which libzero variant to download (default: sqlite)",
    )
    args = p.parse_args(argv)
    assert args.command == "install"
    try:
        path = _native._resolve_libs_dir(args.backend)
        print(f"libzero installed at: {path}")
        return 0
    except Exception as e:
        print(f"install failed: {e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
