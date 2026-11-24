// Sender (runs on the laptop)
//
//  1. creates a virtual extended display (private CGVirtualDisplay API)
//  2. captures it with ScreenCaptureKit
//  3. encodes with VideoToolbox (H.264 or HEVC)
//  4. streams to the receiver on the iMac over TCP
//
// Needs "Screen Recording" permission for the app you launch it from (Terminal etc).

import AppKit
import CoreGraphics
import CoreMedia
import Network
import ScreenCaptureKit
import VideoToolbox

// MARK: - Options

struct Options {
    var width = 1920          // logical (point) size of the virtual display
    var height = 1080
    var hidpi = true          // true => pixel size is 2x (3840x2160 by default)
    var fps = 60
    var mbps = 60
    var codec = Codec.h264
    var keepAwake = false     // prevent the Mac from sleeping while the sender runs
    var host: String? = nil   // nil => discover receiver via Bonjour
    var port = defaultPort
}

// MARK: - Saved settings (UserDefaults) + Settings window

let presets: [(name: String, w: Int, h: Int, hidpi: Bool)] = [
    ("4K stream: 1920×1080 HiDPI (lightest, lowest latency)", 1920, 1080, true),
    ("5K stream: 2560×1440 HiDPI (sharpest)", 2560, 1440, true),
    ("2560×1440, no HiDPI (light, softer)", 2560, 1440, false),
]

func loadSavedOptions() -> Options {
    var o = Options()
    let d = UserDefaults.standard
    if let h = d.string(forKey: "host"), !h.isEmpty { o.host = h }
    if d.object(forKey: "preset") != nil {
        let p = presets[min(max(d.integer(forKey: "preset"), 0), presets.count - 1)]
        o.width = p.w; o.height = p.h; o.hidpi = p.hidpi
    }
    if d.object(forKey: "fps") != nil { o.fps = d.integer(forKey: "fps") }
    if d.object(forKey: "mbps") != nil { o.mbps = d.integer(forKey: "mbps") }
    if d.object(forKey: "codec") != nil { o.codec = d.integer(forKey: "codec") == 1 ? .hevc : .h264 }
    o.keepAwake = d.bool(forKey: "keepAwake")
    return o
}

/// The display and encoder are configured once at startup, so applying new settings = relaunch the app.
func relaunchApp() {
    let path = Bundle.main.bundlePath
    if path.hasSuffix(".app") {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/bin/sh")
        t.arguments = ["-c", "sleep 1; open -n \"\(path)\""]
        try? t.run()
    } else {
        print("Settings saved. Start the sender again to apply them.")
    }
    exit(0)
}

final class SettingsController: NSObject {
    private var window: NSWindow?
    private let host = NSTextField()
    private let quality = NSPopUpButton()
    private let fps = NSPopUpButton()
    private let mbps = NSTextField()
    private let codec = NSPopUpButton()
    private let keepAwake = NSButton(checkboxWithTitle: "Keep this Mac awake while streaming", target: nil, action: nil)

    @objc func show() {
        if window == nil { build() }
        load()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func row(_ title: String, y: CGFloat, _ control: NSView, width: CGFloat = 280) {
        let l = NSTextField(labelWithString: title)
        l.frame = NSRect(x: 16, y: y + 2, width: 130, height: 20)
        l.alignment = .right
        control.frame = NSRect(x: 156, y: y, width: width, height: 24)
        window?.contentView?.addSubview(l)
        window?.contentView?.addSubview(control)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 345),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "iMac Display Sender: Settings"
        w.isReleasedWhenClosed = false
        w.center()
        window = w

        host.placeholderString = "empty = find the iMac automatically"
        quality.addItems(withTitles: presets.map { $0.name })
        fps.addItems(withTitles: ["30", "60"])
        codec.addItems(withTitles: ["H.264 (compatible)", "HEVC (efficient, needs fast decoder)"])
        row("iMac address", y: 295, host)
        row("Quality", y: 255, quality)
        row("Frame rate", y: 215, fps, width: 90)
        row("Bitrate (Mbit/s)", y: 175, mbps, width: 90)
        row("Codec", y: 135, codec)
        keepAwake.frame = NSRect(x: 156, y: 98, width: 300, height: 24)
        w.contentView?.addSubview(keepAwake)

        let hint = NSTextField(wrappingLabelWithString:
            "Tip: with a direct cable, enter the iMac's 169.254.x.x address (the receiver shows it on its waiting screen). Saving restarts this app.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: 44, width: 430, height: 40)
        w.contentView?.addSubview(hint)

        let save = NSButton(title: "Save & Restart", target: self, action: #selector(saveAndRestart))
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 330, y: 8, width: 130, height: 30)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 240, y: 8, width: 84, height: 30)
        w.contentView?.addSubview(save)
        w.contentView?.addSubview(cancel)
    }

    private func load() {
        let o = loadSavedOptions()
        host.stringValue = o.host ?? ""
        quality.selectItem(at: presets.firstIndex { $0.w == o.width && $0.h == o.height && $0.hidpi == o.hidpi } ?? 0)
        fps.selectItem(withTitle: "\(o.fps)")
        mbps.integerValue = o.mbps
        codec.selectItem(at: o.codec == .hevc ? 1 : 0)
        keepAwake.state = o.keepAwake ? .on : .off
    }

    @objc private func cancel() { window?.orderOut(nil) }

    @objc private func saveAndRestart() {
        let d = UserDefaults.standard
        d.set(host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "host")
        d.set(quality.indexOfSelectedItem, forKey: "preset")
        d.set(Int(fps.titleOfSelectedItem ?? "60") ?? 60, forKey: "fps")
        d.set(max(5, min(300, mbps.integerValue)), forKey: "mbps")
        d.set(codec.indexOfSelectedItem, forKey: "codec")
        d.set(keepAwake.state == .on, forKey: "keepAwake")
        d.set(true, forKey: "configured")
        d.synchronize()
        relaunchApp()
    }
}

func usage() -> Never {
    print("""
    usage: sender [--host IP] [--port N] [--size WxH] [--no-hidpi] [--fps N] [--mbps N] [--codec h264|hevc]

      --host    receiver address (default: auto-discover via Bonjour)
      --size    logical size of the virtual display, default 1920x1080
                (with HiDPI the stream is 2x that: 3840x2160; use 2560x1440 for the full 5K
                 5120x2880 stream, which is sharper but adds noticeable latency)
      --no-hidpi  stream exactly WxH pixels (lighter, less sharp)
      --fps     frames per second, default 60
      --mbps    target bitrate in Mbit/s, default 60
      --codec   h264 (default, safest) or hevc (better quality per bit)
    """)
    exit(2)
}

func parseArgs() -> Options {
    var o = loadSavedOptions()   // saved settings first; command-line flags override them
    var a = Array(CommandLine.arguments.dropFirst())
    func next() -> String { guard !a.isEmpty else { usage() }; return a.removeFirst() }
    while !a.isEmpty {
        switch a.removeFirst() {
        case "--host": o.host = next()
        case "--port": o.port = UInt16(next()) ?? defaultPort
        case "--size":
            let p = next().split(separator: "x").compactMap { Int($0) }
            guard p.count == 2 else { usage() }
            o.width = p[0]; o.height = p[1]
        case "--no-hidpi": o.hidpi = false
        case "--fps": o.fps = Int(next()) ?? 60
        case "--mbps": o.mbps = Int(next()) ?? 60
        case "--codec":
            switch next() {
            case "h264": o.codec = .h264
            case "hevc": o.codec = .hevc
            default: usage()
            }
        default: usage()
        }
    }
    return o
}

// MARK: - Network link (connects to the receiver, reconnects forever)

final class Link {
    let host: String?
    let port: UInt16
    let queue: DispatchQueue
    private var conn: NWConnection?
    private var browser: NWBrowser?
    private(set) var ready = false
    private(set) var inflight = 0
    var onReady: (() -> Void)?
    var onState: ((Bool) -> Void)?   // true = connected

    init(host: String?, port: UInt16, queue: DispatchQueue) {
        self.host = host; self.port = port; self.queue = queue
    }

    func start() {
        queue.async { self.connect() }
    }

    private func connect() {
        if let host = host {
            open(.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!))
        } else {
            print("Looking for receiver via Bonjour...")
            let b = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
            b.browseResultsChangedHandler = { [weak self, weak b] results, _ in
                guard let self = self, let b = b, let r = results.first else { return }
                b.cancel()
                self.browser = nil
                print("Found receiver: \(r.endpoint)")
                self.open(r.endpoint)
            }
            b.start(queue: queue)
            browser = b
        }
    }

    private func open(_ endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        (params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options)?.noDelay = true
        let c = NWConnection(to: endpoint, using: params)
        conn = c
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self = self, let c = c, c === self.conn else { return }
            switch state {
            case .ready:
                print("Connected to receiver.")
                self.ready = true
                self.inflight = 0
                self.watchForClose(c)
                self.onState?(true)
                self.onReady?()
            case .failed, .waiting:
                self.fail(c)
            default: break
            }
        }
        c.start(queue: queue)
    }

    // The receiver never sends data; a receive completing means the connection closed.
    private func watchForClose(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, done, err in
            guard let self = self, c === self.conn else { return }
            if err != nil || done { self.fail(c) } else { self.watchForClose(c) }
        }
    }

    private func fail(_ c: NWConnection) {
        guard c === conn else { return }
        print("Disconnected, retrying...")
        conn = nil
        ready = false
        onState?(false)
        c.cancel()
        queue.asyncAfter(deadline: .now() + 1) { self.connect() }
    }

    func send(_ m: FrameMessage) {
        guard ready, let c = conn else { return }
        inflight += 1
        c.send(content: m.encode(), completion: .contentProcessed { [weak self] _ in
            self?.queue.async { self?.inflight -= 1 }
        })
    }
}

// MARK: - Encoder

final class Encoder {
    private var session: VTCompressionSession?
    let codec: Codec
    var forceKey = false
    var onMessage: ((FrameMessage) -> Void)?

    init?(width: Int, height: Int, fps: Int, mbps: Int, codec: Codec) {
        self.codec = codec
        var s: VTCompressionSession?
        let ct: CMVideoCodecType = codec == .h264 ? kCMVideoCodecType_H264 : kCMVideoCodecType_HEVC
        let st = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height), codecType: ct,
            encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard st == noErr, let s = s else {
            print("VTCompressionSessionCreate failed: \(st)")
            return nil
        }
        func set(_ k: CFString, _ v: CFTypeRef) { VTSessionSetProperty(s, key: k, value: v) }
        let bps = mbps * 1_000_000
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_ProfileLevel,
            codec == .h264 ? kVTProfileLevel_H264_High_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel)
        set(kVTCompressionPropertyKey_AverageBitRate, bps as CFNumber)
        set(kVTCompressionPropertyKey_DataRateLimits, [bps / 8 * 2, 1] as CFArray)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, fps as CFNumber)
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval, (fps * 2) as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(s)
        session = s
    }

    func encode(_ pb: CVPixelBuffer) {
        guard let session = session else { return }
        var props: CFDictionary?
        if forceKey {
            props = [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary
            forceKey = false
        }
        // Use the host clock for timestamps so they are always strictly increasing,
        // even when we re-encode the last frame for a newly connected receiver.
        let pts = CMClockGetTime(CMClockGetHostTimeClock())
        VTCompressionSessionEncodeFrame(
            session, imageBuffer: pb, presentationTimeStamp: pts, duration: .invalid,
            frameProperties: props, infoFlagsOut: nil
        ) { [weak self] status, _, sb in
            guard status == noErr, let sb = sb, let self = self else {
                if status != noErr { print("encode error: \(status)") }
                return
            }
            self.handle(sb)
        }
    }

    private func handle(_ sb: CMSampleBuffer) {
        guard let bb = CMSampleBufferGetDataBuffer(sb) else { return }
        var isKey = true
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]],
           let d = arr.first, (d[kCMSampleAttachmentKey_NotSync] as? Bool) == true {
            isKey = false
        }
        var params: [Data] = []
        if isKey, let fd = CMSampleBufferGetFormatDescription(sb) {
            var count = 0
            var p: UnsafePointer<UInt8>?
            var size = 0
            func get(_ i: Int) -> OSStatus {
                codec == .h264
                    ? CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                        fd, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &size,
                        parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
                    : CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                        fd, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &size,
                        parameterSetCountOut: &count, nalUnitHeaderLengthOut: nil)
            }
            if get(0) == noErr {
                for i in 0..<count where get(i) == noErr {
                    if let p = p { params.append(Data(bytes: p, count: size)) }
                }
            }
        }
        let len = CMBlockBufferGetDataLength(bb)
        var data = Data(count: len)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            CMBlockBufferCopyDataBytes(bb, atOffset: 0, dataLength: len, destination: raw.baseAddress!) == kCMBlockBufferNoErr
        }
        guard ok else { return }
        onMessage?(FrameMessage(codec: codec, keyframe: isKey, params: params, payload: data))
    }
}

// MARK: - Screen capture

final class Capture: NSObject, SCStreamOutput, SCStreamDelegate {
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onStop: ((Error) -> Void)?
    private(set) var isRunning = false
    private var stream: SCStream?

    func start(displayID: CGDirectDisplayID, width: Int, height: Int, fps: Int, queue: DispatchQueue) async throws {
        var found: SCDisplay?
        for _ in 0..<40 { // the new display can take a moment to show up
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            found = content.displays.first { $0.displayID == displayID }
            if found != nil { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard let display = found else {
            throw NSError(domain: "sender", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "virtual display not visible to ScreenCaptureKit"])
        }
        let cfg = SCStreamConfiguration()
        cfg.width = width
        cfg.height = height
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        cfg.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        cfg.colorSpaceName = CGColorSpace.sRGB
        cfg.showsCursor = true
        cfg.queueDepth = 6
        let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                         configuration: cfg, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await s.startCapture()
        stream = s
        isRunning = true
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid,
              let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = arr.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        onFrame?(pb)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Happens e.g. when the Mac sleeps. Don't quit: the owner restarts capture.
        print("Capture stopped: \(error.localizedDescription)")
        isRunning = false
        onStop?(error)
    }
}

// MARK: - Main

setvbuf(stdout, nil, _IOLBF, 0)
let opt = parseArgs()
let scale = opt.hidpi ? 2 : 1
let pxW = opt.width * scale
let pxH = opt.height * scale

// ScreenCaptureKit / CGVirtualDisplay need a WindowServer connection even for a CLI tool.
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon; menu bar item only

// Menu bar item: status + Quit
let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
statusItem.button?.title = "🖥"
let statusLine = NSMenuItem(title: "Starting...", action: nil, keyEquivalent: "")
let statusMenu = NSMenu()
let settingsController = SettingsController()
statusMenu.addItem(statusLine)
statusMenu.addItem(NSMenuItem.separator())
let settingsItem = NSMenuItem(title: "Settings…", action: #selector(SettingsController.show), keyEquivalent: ",")
settingsItem.target = settingsController
statusMenu.addItem(settingsItem)
statusMenu.addItem(NSMenuItem.separator())
statusMenu.addItem(withTitle: "Quit iMac Display Sender", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
statusItem.menu = statusMenu
func setStatus(_ s: String) { DispatchQueue.main.async { statusLine.title = s } }

func fatal(_ message: String) -> Never {
    print(message)
    DispatchQueue.main.async {
        app.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "iMac Display Sender"
        alert.informativeText = message
        alert.runModal()
        exit(1)
    }
    while true { sleep(1) }
}

// 1. Virtual display
let desc = CGVirtualDisplayDescriptor()
desc.queue = DispatchQueue.main
desc.name = "iMac Display"
desc.vendorID = 0x3456
desc.productID = 0x1234
desc.serialNum = 1
desc.maxPixelsWide = UInt32(pxW)
desc.maxPixelsHigh = UInt32(pxH)
desc.sizeInMillimeters = CGSize(width: 597, height: 336) // 27" 16:9
guard let vdisplay = CGVirtualDisplay(descriptor: desc) else {
    print("Could not create virtual display (private API changed?)")
    exit(1)
}
let settings = CGVirtualDisplaySettings()
settings.hiDPI = opt.hidpi ? 1 : 0
settings.modes = [CGVirtualDisplayMode(width: UInt(opt.width), height: UInt(opt.height), refreshRate: Double(opt.fps))]
guard vdisplay.apply(settings) else {
    print("Could not apply virtual display settings")
    exit(1)
}
print("Virtual display \(vdisplay.displayID): \(opt.width)x\(opt.height) points, \(pxW)x\(pxH) pixels, \(opt.fps) fps")
print("Arrange it in System Settings > Displays like any other monitor.")

// 2-4. capture -> encode -> network, all serialized on one queue
let work = DispatchQueue(label: "sender.work")
let link = Link(host: opt.host, port: opt.port, queue: work)
guard let encoder = Encoder(width: pxW, height: pxH, fps: opt.fps, mbps: opt.mbps, codec: opt.codec) else { exit(1) }
let capture = Capture()
var lastFrame: CVPixelBuffer? // kept so a newly connected receiver gets an image even if the screen is idle

// Diagnostics (all touched only on the `work` queue)
var nCaptured = 0, nEncoded = 0, nDropped = 0, lastSeenCaptured = 0

encoder.onMessage = { m in
    work.async {
        nEncoded += 1
        if nEncoded <= 3 { print("first messages: codec \(m.codec) key \(m.keyframe) params \(m.params.count) bytes \(m.payload.count)") }
        link.send(m)
    }
}
link.onState = { connected in
    setStatus(connected ? "Connected to receiver" : "Waiting for receiver...")
}
link.onReady = {
    encoder.forceKey = true
    if let pb = lastFrame { encoder.encode(pb) }
}
capture.onFrame = { pb in
    nCaptured += 1
    lastFrame = pb
    // Drop (before encoding, so the decoder never sees a gap) if the network can't keep up.
    guard link.ready, link.inflight < 3 else { nDropped += 1; return }
    encoder.encode(pb)
}

// Every 2 s: print stats, and if the screen has been idle re-send the last frame
// (ScreenCaptureKit only delivers frames when something changes).
let statsTimer = DispatchSource.makeTimerSource(queue: work)
statsTimer.schedule(deadline: .now() + 2, repeating: 2)
statsTimer.setEventHandler {
    print("captured \(nCaptured)  dropped \(nDropped)  sent \(nEncoded)  connected \(link.ready)")
    if link.ready, nCaptured == lastSeenCaptured, let pb = lastFrame, link.inflight < 3 {
        encoder.encode(pb)
    }
    lastSeenCaptured = nCaptured
}
statsTimer.resume()

// Optionally keep the Mac awake while we are running.
var awakeActivity: NSObjectProtocol?
if opt.keepAwake {
    awakeActivity = ProcessInfo.processInfo.beginActivity(
        options: [.idleSystemSleepDisabled, .idleDisplaySleepDisabled], reason: "Streaming to iMac")
}

// Capture stops when the Mac sleeps. Restart it (retrying for a while, e.g. while the screen is
// locked after wake); if it cannot be restored, relaunch the whole app.
var restarting = false
func restartCapture() {
    DispatchQueue.main.async {
        guard !restarting else { return }
        restarting = true
        setStatus("Capture interrupted, restarting...")
        Task {
            for attempt in 1...40 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                do {
                    try await capture.start(displayID: vdisplay.displayID, width: pxW, height: pxH,
                                            fps: opt.fps, queue: work)
                    print("Capture restarted")
                    setStatus(link.ready ? "Connected to receiver" : "Waiting for receiver...")
                    restarting = false
                    return
                } catch {
                    print("capture restart attempt \(attempt) failed: \(error.localizedDescription)")
                }
            }
            print("Could not restore capture, relaunching")
            relaunchApp()
        }
    }
}
capture.onStop = { _ in restartCapture() }
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
        if !capture.isRunning { restartCapture() }
    }
}

Task {
    do {
        try await capture.start(displayID: vdisplay.displayID, width: pxW, height: pxH, fps: opt.fps, queue: work)
        print("Capturing. Streaming to \(opt.host ?? "Bonjour-discovered receiver")...")
        setStatus("Waiting for receiver...")
        link.start()
    } catch {
        fatal("Screen capture failed: \(error.localizedDescription)\n\n"
              + "Allow this app in System Settings > Privacy & Security > Screen Recording, then open it again.")
    }
}

// First launch: ask for the iMac's address etc.
if !UserDefaults.standard.bool(forKey: "configured") {
    DispatchQueue.main.async { settingsController.show() }
}

app.run()
