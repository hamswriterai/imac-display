# iMac Display

**Use an old 5K iMac as a second screen for another Mac.**

Apple removed Target Display Mode from the 2015 and later Retina iMacs, and the iMac's
Thunderbolt ports carry data only, with no video input. So you can't plug a MacBook into an iMac
and use it as a monitor, and no software can change that: the hardware has no path to feed
video into the panel.

iMac Display works around it in software. The MacBook creates a virtual extended display,
captures it, encodes it as H.264 or HEVC and streams it over the network to a small
fullscreen app on the iMac. You get a real extra desktop, with the iMac's great screen, that you
arrange in System Settings > Displays like any monitor.

```
 MacBook (sender)                                          iMac (receiver)
 ┌──────────────────────────────┐   TCP over Ethernet/    ┌───────────────────────────┐
 │ virtual display              │   Thunderbolt Bridge/   │ decode (VideoToolbox)     │
 │ -> ScreenCaptureKit          │   Wi-Fi                 │ -> AVSampleBufferDisplay  │
 │ -> VideoToolbox H.264/HEVC   │ ──────────────────────> │    Layer, fullscreen      │
 └──────────────────────────────┘                         └───────────────────────────┘
```

Display only: the mouse and keyboard stay on the MacBook, and the cursor simply moves onto the
iMac's screen. There is no audio.

## Requirements

| | |
|---|---|
| Sender (the computer) | Any Mac, Apple Silicon or Intel, on **macOS 12.3 or later** |
| Receiver (the iMac) | Any Mac on **macOS 12.0 or later**; built and tested on a 27" 5K iMac running macOS 12.7 |
| Network | A wired link is strongly recommended, see [Connecting the Macs](#connecting-the-macs) |

The apps are universal binaries (Intel and Apple Silicon), so the same DMG works on every Mac.

## Install

### Option 1: download the DMG
Download `iMacDisplay.dmg` from the [Releases](../../releases) page (if the repository has one),
or build it yourself (below). Open it and drag **both** apps to `/Applications` on every Mac you
want to use:

- **iMac Display Receiver**, run on the iMac (the screen)
- **iMac Display Sender**, run on the Mac whose desktop you want to extend

### Option 2: build it
You need the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/hamswriterai/imac-display.git
cd imac-display
make dmg          # builds both apps and build/iMacDisplay.dmg
```

`make` alone builds just the two binaries into `build/`.

### First launch: Gatekeeper
The apps are signed ad hoc, not with a paid Apple Developer ID, and are not notarized. The first
time you open each app, macOS will say it can't verify the developer. Right-click the app and
choose **Open**, then **Open** again. Or remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine "/Applications/iMac Display Sender.app"
xattr -dr com.apple.quarantine "/Applications/iMac Display Receiver.app"
```

## Set up

1. **iMac:** open *iMac Display Receiver*. It goes fullscreen and shows
   "Waiting for sender", along with this iMac's IP address(es). Esc or Cmd-Q quits it.
2. **MacBook:** open *iMac Display Sender*. It lives in the menu bar (🖥) and has no Dock icon.
   - On first launch the **Settings** window opens. Enter the iMac's address from step 1, or leave
     it empty to find the iMac automatically, then click **Save & Restart**.
   - When asked, allow **Screen Recording**: System Settings > Privacy & Security > Screen &
     System Audio Recording. Then open the app again.
3. A new display named "iMac Display" appears. Arrange it in **System Settings > Displays**.
   The iMac should leave its waiting screen and show your extra desktop.

Settings are remembered on each Mac. Repeat step 2 once on every Mac you want to use as a sender.

### Settings

Open them from the 🖥 menu > Settings... Saving restarts the sender.

| Setting | Meaning |
|---|---|
| iMac address | The receiver's IP address. Empty means find it automatically via Bonjour. |
| Quality | 4K stream (1920x1080 HiDPI, the default, lightest and lowest latency), 5K stream (2560x1440 HiDPI, sharpest, noticeable latency), or 2560x1440 without HiDPI. |
| Frame rate | 30 or 60 fps. |
| Bitrate | Target Mbit/s. 60 is a good start; lower it on a slow link. |
| Codec | H.264 (works everywhere) or HEVC (better quality per bit, needs a fast decoder on the iMac). |
| Keep this Mac awake | Prevents the sender Mac from sleeping while it runs. Off by default. |

The sender also takes command-line flags, which override the saved settings for that run:

```sh
"/Applications/iMac Display Sender.app/Contents/MacOS/sender" --help
```

## Connecting the Macs

The stream needs about 60 Mbit/s at the default settings. What matters most for smoothness is a
steady link, so wired beats Wi-Fi.

1. **Direct Ethernet cable, Mac to Mac** (recommended, simplest and lowest latency): the iMac has a Gigabit
   Ethernet port, and the other Mac needs a USB-C or Thunderbolt Ethernet adapter. With no router,
   each Mac gets a self-assigned `169.254.x.x` address. **Enter the iMac's `169.254.x.x` address**
   (shown on the receiver's waiting screen) in the sender's Settings, which also guarantees the
   stream uses the cable even if Wi-Fi is on. Keep Wi-Fi enabled for internet.
2. **Both on a router by cable:** works the same way; address or auto-discovery.
3. **Thunderbolt Bridge:** a Thunderbolt cable (an adapter if the ports differ, such as
   Thunderbolt 3 to Thunderbolt 2) with Thunderbolt Bridge enabled in System Settings > Network.
4. **Wi-Fi:** works, but latency is noticeably higher and less steady.

## Known limitations

- **5K latency.** The full 5120x2880 stream shows significant latency, even with a fast sender
  such as an M1 Max, mostly from the decoder on the older iMac. The default is therefore the 4K
  stream (3840x2160), which the iMac scales up to its 5K panel; it is much smoother. Ideas for
  fixing 5K are welcome, see [Contributing](#contributing).
- **No app icons.** Both apps use the default generic icon. Contributions welcome.
- **No audio, and no mouse/keyboard forwarding.** The iMac is a display only.
- **One sender per receiver.** A second sender replaces the first.
- **Not notarized.** See [First launch](#first-launch-gatekeeper).
- **Uses a private macOS API** (`CGVirtualDisplay`, the same one DeskPad and BetterDisplay use).
  A future macOS release could break it.
- Traffic is **not encrypted or authenticated**. Anyone on the same network who can reach the
  receiver's port can send it video. Use a direct cable or a network you trust.

## Troubleshooting

**"iMac Display Sender would like to record this computer's screen", or "The user declined
TCCs", even though the toggle is on.**
The apps are signed ad hoc, so every new build has a different code identity, and macOS ties
the Screen Recording permission to that exact identity. After you **install a new version**,
the old permission no longer matches. Clear it, then grant it again:

```sh
tccutil reset ScreenCapture local.imacdisplay.sender
```

(Or select "iMac Display Sender" in System Settings > Privacy & Security > Screen & System Audio
Recording and click **-** to remove it.) Then open the sender, allow the prompt, and open it
once more. Signing with a stable certificate would remove this step, see Contributing.

**The iMac stays on "Waiting for sender".**
- Make sure the sender's Settings contain the iMac's current address (it is shown on the waiting
  screen). Direct-cable `169.254.x.x` addresses can change if the cable is unplugged for a while.
- From the sender Mac, `ping <iMac address>` should answer. If not, it is a cable, adapter or
  network problem.
- `nc -zv <iMac address> 7777` should say "succeeded". "Connection refused" means the receiver is
  not listening: quit it (Esc) and open it again. A timeout means a firewall is dropping it.
- A macOS firewall prompt ("accept incoming connections?") can hide behind the fullscreen
  receiver. Quit and reopen it, then click Allow.
- To see logs, run the apps from Terminal:
  ```sh
  "/Applications/iMac Display Receiver.app/Contents/MacOS/receiver"
  "/Applications/iMac Display Sender.app/Contents/MacOS/sender"
  ```
  The sender prints `captured / dropped / sent` counters every 2 seconds.

**Laggy or choppy picture.**
- Use a wired connection, and the 4K stream quality (the default).
- Lower the frame rate to 30 and the bitrate to 30.
- Watch the iMac in Activity Monitor: if the receiver or `VTDecoderXPCService` is at high CPU,
  the iMac's decoder is the bottleneck, so use a lighter quality.

**The sender stopped after the MacBook slept.**
It should restart capture automatically within a few seconds of waking. If you would rather the
Mac not sleep while streaming, enable *Keep this Mac awake while streaming* in Settings.

**No new display appears on the sender Mac.**
Check that Screen Recording is allowed (see above). The virtual display only exists while the
sender runs.

## Contributing

Improvements are very welcome, from small fixes to big features. See
[CONTRIBUTING.md](CONTRIBUTING.md). Good places to start:

- Make 5K smooth: lower-latency decode on the iMac, frame skipping when it falls behind,
  hardware HEVC where available, and a latency readout.
- App icons for both apps.
- Stable code signing and notarization, to remove the Gatekeeper and permission steps.
- Mouse and keyboard forwarding from the iMac back to the sender, and audio.
- Encrypted or paired connections.
- A first-run guide, and a proper preferences window with live apply.

## How it works

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## License

Free to use, modify and share, but not to sell. See [LICENSE](LICENSE): it is the MIT license
plus a condition that the software may not be sold or otherwise charged for. Because of that
condition it is *source-available* and not an OSI-approved "open source" license.
