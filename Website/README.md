# Website/

This is the built site, committed so the VPS deploy account can publish it
without a macOS build on the server. `python3 tools/build-site.py --output
Website` (or `make site`) regenerates it on a Mac — the script downscales the
screenshots with `sips`, which only exists there. Commit the result.
