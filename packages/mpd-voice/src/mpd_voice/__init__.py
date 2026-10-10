"""Voice control for MPD: microphone -> local speech recognition -> MPD.

The package has no third-party dependencies: the MPD protocol client, the
audio capture, the VAD and the HTTP speech clients are all standard library
code.  Speech recognition itself is delegated to a local backend (the repo's
whisper.cpp stack, `whisper-cli`, or any command that prints a transcript).
"""

__version__ = "0.1.0"

__all__ = ["__version__"]
