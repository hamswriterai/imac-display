# Architecture

Two small apps and one shared file. No third-party dependencies.

```
sender (MacBook)
  CGVirtualDisplay (private API)   creates an extended display, optionally HiDPI
  ScreenCaptureKit (SCStream)      captures that display as YUV 4:2:0 frames
  VideoToolbox (VTCompressionSession)  H.264 or HEVC, real time, no B-frames
  Network.framework (NWConnection) sends length-prefixed frames over TCP

receiver (iMac)
  Network.framework (NWListener)   accepts one sender; advertises _imacdisplay._tcp via Bonjour
  CoreMedia                        rebuilds a format description from SPS/PPS and wraps frames
  AVSampleBufferDisplayLayer       decodes (VideoToolbox) and displays immediately
  AppKit                           borderless fullscreen window, waiting screen with local IPs
```

## Wire protocol (`Shared/Common.swift`)

A TCP stream of messages:

```
u32  body length (big endian)
u8   codec            0 = H.264, 1 = HEVC
u8   keyframe flag
u8   number of parameter sets (only present with keyframes)
     [u16 length + bytes] per parameter set (SPS, PPS[, VPS])
...  frame data in AVCC form (4-byte length-prefixed NAL units)
```

There is no handshake, authentication or encryption.

## Behavior worth knowing

- **Back-pressure.** If the network can't keep up (more than 3 sends in flight) the sender drops
  frames *before* encoding, so the decoder never sees a missing reference frame.
- **Keyframes.** A keyframe is forced whenever a receiver connects, and then every 2 seconds. The
  last captured frame is kept, and re-sent when the screen is idle, so a receiver that connects
  to a static desktop still gets an image.
- **Timestamps** come from the host clock, so they always increase, and frames are marked
  "display immediately" on the receiver: it is a live display, not a player.
- **Reconnection.** The sender reconnects forever (and finds the receiver again through
  Bonjour). The receiver restarts its listener when the network changes.
- **Sleep.** When the sender Mac sleeps, ScreenCaptureKit stops. The sender restarts capture
  on wake, and relaunches itself if that fails for ~80 seconds.
- **Settings** are stored in `UserDefaults`; the display and encoder are configured once at
  startup, so saving settings relaunches the app.
- **Permissions.** Screen Recording is tied by macOS to the app's code identity; ad-hoc builds
  get a new identity per build (see README).

## Why not true Target Display Mode?

The 2015+ Retina iMacs have no video-input path. The panel is driven by the iMac's own GPU
through an internal timing controller, and the Thunderbolt ports are data-only for video-in.
That is a hardware limit, so streaming is the only software option.
