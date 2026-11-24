// Receiver (runs on the iMac)
//
// Listens for the sender, decodes the H.264/HEVC stream and shows it fullscreen.
// Quit with Esc or Cmd-Q. Run with --windowed to test in a normal window.

import AppKit
import AVFoundation
import CoreMedia
import Network

// MARK: - Options

var listenPort = defaultPort
var windowed = false
do {
    var a = Array(CommandLine.arguments.dropFirst())
    while !a.isEmpty {
        switch a.removeFirst() {
        case "--port": if !a.isEmpty { listenPort = UInt16(a.removeFirst()) ?? defaultPort }
        case "--windowed": windowed = true
        default:
            print("usage: receiver [--port N] [--windowed]")
            exit(2)
        }
    }
}

// MARK: - Local addresses (shown on the waiting screen so you know what to type into the sender)

func localIPv4Addresses() -> [(iface: String, ip: String)] {
    var result: [(String, String)] = []
    var ifap: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
    defer { freeifaddrs(ifap) }
    var p: UnsafeMutablePointer<ifaddrs>? = first
    while let cur = p {
        defer { p = cur.pointee.ifa_next }
        guard let sa = cur.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
              (cur.pointee.ifa_flags & UInt32(IFF_LOOPBACK)) == 0, (cur.pointee.ifa_flags & UInt32(IFF_UP)) != 0
        else { continue }
        let name = String(cString: cur.pointee.ifa_name)
        guard name.hasPrefix("en") else { continue } // Ethernet / Wi-Fi / Thunderbolt Bridge
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            result.append((name, String(cString: host)))
        }
    }
    return result
}

func waitingText() -> String {
    let addrs = localIPv4Addresses().map { "\($0.ip)   (\($0.iface))" }.joined(separator: "\n")
    return "Waiting for sender on port \(listenPort)...\n\n"
        + "This iMac's address:\n\(addrs.isEmpty ? "(no network connection)" : addrs)\n\n"
        + "Enter one of these in the sender's Settings, or leave it empty to auto-discover.\n(Esc quits)"
}

// MARK: - Video view

final class VideoView: NSView {
    override func makeBackingLayer() -> CALayer {
        let l = AVSampleBufferDisplayLayer()
        l.videoGravity = .resizeAspect
        l.backgroundColor = NSColor.black.cgColor
        return l
    }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Decoder / renderer (AVSampleBufferDisplayLayer decodes via VideoToolbox, hardware if available)

final class Renderer {
    let layer: AVSampleBufferDisplayLayer
    var onFirstFrame: (() -> Void)?
    private var format: CMVideoFormatDescription?
    private var lastParams: [Data] = []
    private var lastCodec: Codec?
    private var haveKey = false
    private var shownFirst = false

    init(layer: AVSampleBufferDisplayLayer) { self.layer = layer }

    private var logged = 0

    func reset() {
        logged = 0
        format = nil; lastParams = []; lastCodec = nil; haveKey = false; shownFirst = false
        layer.flushAndRemoveImage()
    }

    private func makeFormat(_ m: FrameMessage) -> CMVideoFormatDescription? {
        let ptrs = m.params.map { d -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: max(d.count, 1))
            d.copyBytes(to: p, count: d.count)
            return p
        }
        defer { ptrs.forEach { $0.deallocate() } }
        let cptrs = ptrs.map { UnsafePointer($0) }
        let sizes = m.params.map { $0.count }
        var out: CMVideoFormatDescription?
        let st: OSStatus
        switch m.codec {
        case .h264:
            st = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: nil, parameterSetCount: cptrs.count, parameterSetPointers: cptrs,
                parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &out)
        case .hevc:
            st = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: nil, parameterSetCount: cptrs.count, parameterSetPointers: cptrs,
                parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &out)
        }
        if st != noErr { print("format description failed: \(st)") }
        return st == noErr ? out : nil
    }

    func handle(_ m: FrameMessage) {
        if logged < 5 {
            logged += 1
            print("received: codec \(m.codec) key \(m.keyframe) params \(m.params.count) bytes \(m.payload.count) layerStatus \(layer.status.rawValue)")
        }
        if m.keyframe, !m.params.isEmpty, m.params != lastParams || m.codec != lastCodec {
            format = makeFormat(m)
            print("format description: \(format == nil ? "FAILED" : "ok")")
            lastParams = m.params
            lastCodec = m.codec
            layer.flush()
        }
        if m.keyframe { haveKey = true }
        guard haveKey, let format = format else { return }

        if layer.status == .failed {
            print("display layer failed: \(layer.error.map { "\($0)" } ?? "unknown"); resyncing")
            layer.flush()
            haveKey = m.keyframe     // wait for the next keyframe to resync
            if !m.keyframe { return }
        }

        let n = m.payload.count
        var bb: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: n, blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil, offsetToData: 0, dataLength: n, flags: 0, blockBufferOut: &bb) == kCMBlockBufferNoErr,
            let block = bb else { return }
        let copied = m.payload.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: n)
        }
        guard copied == kCMBlockBufferNoErr else { return }

        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var size = n
        var sb: CMSampleBuffer?
        guard CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size,
            sampleBufferOut: &sb) == noErr, let sample = sb else { return }

        // Show immediately; we are a live display, not a player.
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(arr) > 0 {
            let d = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(d,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        layer.enqueue(sample)

        if !shownFirst {
            shownFirst = true
            onFirstFrame?()
        }
    }
}

// MARK: - Network server (one sender at a time; a new one replaces the old)

final class Server {
    let queue = DispatchQueue(label: "receiver.net")
    private var listener: NWListener?
    private var current: NWConnection?
    private var parser = StreamParser()
    let renderer: Renderer
    var onDisconnect: (() -> Void)?

    init(renderer: Renderer) { self.renderer = renderer }

    private var port: UInt16 = defaultPort
    private var monitor: NWPathMonitor?
    var onNetworkChange: (() -> Void)?

    func start(port: UInt16) {
        self.port = port
        queue.async { self.listen() }

        // When the network changes (cable plugged in, Wi-Fi switch...) the listener can silently
        // stop working, so restart it. An already-connected sender is not affected.
        let m = NWPathMonitor()
        var first = true
        m.pathUpdateHandler = { [weak self] _ in
            if first { first = false; return }
            self?.queue.asyncAfter(deadline: .now() + 1) {
                print("Network changed, restarting listener")
                self?.listen()
                DispatchQueue.main.async { self?.onNetworkChange?() }
            }
        }
        m.start(queue: queue)
        monitor = m
    }

    private func listen() {
        listener?.cancel()
        listener = nil
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        (params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options)?.noDelay = true
        do {
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            l.service = NWListener.Service(name: Host.current().localizedName ?? "iMac", type: serviceType)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { [weak self, weak l] state in
                if case .failed(let e) = state {
                    print("listener failed: \(e), retrying")
                    self?.queue.asyncAfter(deadline: .now() + 2) {
                        if self?.listener === l { self?.listen() }
                    }
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            print("could not listen on port \(port): \(error), retrying")
            queue.asyncAfter(deadline: .now() + 2) { self.listen() }
        }
    }

    private func accept(_ c: NWConnection) {
        print("Sender connected: \(c.endpoint)")
        current?.cancel()
        current = c
        parser = StreamParser()
        renderer.reset()
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self = self, let c = c, c === self.current else { return }
            if case .failed = state { self.drop(c) }
        }
        c.start(queue: queue)
        receive(c)
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, err in
            guard let self = self, c === self.current else { return }
            if let data = data, !data.isEmpty {
                for body in self.parser.feed(data) {
                    if let m = FrameMessage.decode(body: body) { self.renderer.handle(m) }
                }
            }
            if err != nil || done { self.drop(c); return }
            self.receive(c)
        }
    }

    private func drop(_ c: NWConnection) {
        print("Sender disconnected.")
        c.cancel()
        if c === current { current = nil }
        renderer.reset()
        DispatchQueue.main.async { self.onDisconnect?() }
    }
}

// MARK: - App

final class DisplayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil) } else { super.keyDown(with: event) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var server: Server!
    var label: NSTextField!
    var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ n: Notification) {
        // Menu with Cmd-Q
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu

        // Window
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let style: NSWindow.StyleMask = windowed ? [.titled, .closable, .resizable] : [.borderless]
        let rect = windowed ? NSRect(x: 100, y: 100, width: 1280, height: 720) : screen.frame
        window = DisplayWindow(contentRect: rect, styleMask: style, backing: .buffered, defer: false)
        window.backgroundColor = .black
        let view = VideoView(frame: NSRect(origin: .zero, size: rect.size))
        view.autoresizingMask = [.width, .height]
        window.contentView = view

        label = NSTextField(labelWithString: waitingText())
        label.textColor = NSColor(white: 0.6, alpha: 1)
        label.font = NSFont.systemFont(ofSize: 28)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        label.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        label.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true

        window.makeKeyAndOrderFront(nil)
        if !windowed {
            NSApp.presentationOptions = [.hideDock, .hideMenuBar]
            NSCursor.hide()
        }
        NSApp.activate(ignoringOtherApps: true)

        // Keep the iMac awake while we are a display.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
            reason: "Showing remote display")

        // Streaming
        let renderer = Renderer(layer: view.displayLayer)
        renderer.onFirstFrame = { [weak self] in DispatchQueue.main.async { self?.label.isHidden = true } }
        server = Server(renderer: renderer)
        server.onDisconnect = { [weak self] in
            self?.label.stringValue = waitingText()
            self?.label.isHidden = false
        }
        server.onNetworkChange = { [weak self] in self?.label.stringValue = waitingText() }
        server.start(port: listenPort)
        print("Listening on port \(listenPort) (Bonjour: \(serviceType))")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
