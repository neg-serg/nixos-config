#!/usr/bin/env python3
"""Set the workTitle metaTag inside a MuseScore .mscz (zip) score.

MuseScore takes the score title from the input file name on MIDI import
(no CLI flag exists), so the wrapper exports the mscz first and rewrites
the workTitle metaTag before producing the final PDF.
"""

import os
import re
import sys
import zipfile


def main():
    src = sys.argv[1]
    title = sys.argv[2]
    tmp = src + ".tmp"

    patched = False
    with (
        zipfile.ZipFile(src) as zin,
        zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout,
    ):
        for name in zin.namelist():
            data = zin.read(name)
            if name.endswith(".mscx"):
                xml = data.decode("utf-8")
                xml, n = re.subn(
                    r'<metaTag name="workTitle">[^<]*</metaTag>',
                    lambda m: '<metaTag name="workTitle">'
                    + title
                    + "</metaTag>",
                    xml,
                    count=1,
                )
                if n:
                    patched = True
                data = xml.encode("utf-8")
            zout.writestr(name, data)

    if not patched:
        sys.stderr.write(
            "patch_title: no workTitle metaTag found in %s\n" % src
        )
        sys.exit(1)
    os.replace(tmp, src)


if __name__ == "__main__":
    main()
