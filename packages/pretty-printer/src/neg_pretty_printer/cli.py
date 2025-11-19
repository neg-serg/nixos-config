from __future__ import annotations

import argparse
import os
from . import FileInfoPrinter


def main() -> None:
    p = argparse.ArgumentParser(prog="ppinfo", description="Pretty print file info")
    p.add_argument("paths", nargs="*", help="Files or directories to print info for")
    args = p.parse_args()

    if not args.paths:
        FileInfoPrinter.currentdir(os.getcwd())
        return

    for path in args.paths:
        if os.path.isdir(path):
            FileInfoPrinter.dir(path)
        elif os.path.exists(path):
            FileInfoPrinter.existsfile(path)
        else:
            FileInfoPrinter.nonexistsfile(path)
