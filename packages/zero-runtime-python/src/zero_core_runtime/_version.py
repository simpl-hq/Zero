"""Single source of truth for both the Python package version and the
zero-runtime-libs release tag we depend on.

Bump both together for normal releases. For wrapper-only fixes use a PEP 440
post-release: __version__ = "1.0.0.post1", LIBS_VERSION unchanged.
"""

__version__ = "1.0.0"
LIBS_VERSION = "1.0.0"
