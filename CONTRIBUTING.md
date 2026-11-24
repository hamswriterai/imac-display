# Contributing

Thanks for helping improve iMac Display! Bug reports, fixes, new features, docs and ideas are all
welcome.

## Getting set up

You need a Mac with the Xcode Command Line Tools (`xcode-select --install`). There is no Xcode
project: a `Makefile` calls `swiftc` directly.

```sh
make            # build/sender and build/receiver (universal binaries)
make dmg        # also builds the two .app bundles and build/iMacDisplay.dmg
make clean
```

For quick iteration, run the binaries directly from Terminal so you see their logs:

```sh
build/receiver --windowed     # a normal window instead of fullscreen
build/sender --help
```

Testing the real thing needs two Macs, or one Mac running both with `--host 127.0.0.1`. The sender
needs Screen Recording permission for the app or terminal that launches it. Note that every
rebuild changes the ad-hoc signature, so you may need `tccutil reset ScreenCapture <bundle id>`
(see the README troubleshooting section).

## Layout

| Path | What it is |
|---|---|
| `Sender/main.swift` | The sender: virtual display, capture, encoder, network, menu bar UI, settings |
| `Sender/Bridging.h` | Declarations of the private `CGVirtualDisplay` API |
| `Receiver/main.swift` | The receiver: listener, decoder/renderer, fullscreen window |
| `Shared/Common.swift` | The wire protocol, shared by both |
| `Packaging/` | App bundle metadata and the DMG script |
| `docs/ARCHITECTURE.md` | How the pieces fit together |

## Pull requests

- Keep changes focused, and describe what you changed and how you tested it, ideally with the
  Macs, macOS versions and connection type you used.
- Keep the receiver working on **macOS 12** and the sender on **12.3**: avoid APIs newer than that,
  or guard them with `#available`.
- Match the existing style. The code favors being short and readable over being clever.
- Update the README if you change user-visible behavior or settings.
- Performance work is welcome, but please include numbers (latency, CPU use, bitrate).

## Reporting bugs

Please include: the macOS version and model of both Macs, how they are connected, the sender's
settings, and the Terminal output of both apps (see the README troubleshooting section).

## License of contributions

By contributing, you agree that your contribution is licensed under the project's license (see
[LICENSE](LICENSE)), including its no-sale condition.
