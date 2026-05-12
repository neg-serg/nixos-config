"""Back-compat shim: expose symbols under legacy module name.

This allows existing scripts doing `from pretty_printer import PrettyPrinter` to
continue working after the library was renamed to `neg_pretty_printer`.
"""

from neg_pretty_printer import *  # noqa: F401,F403
