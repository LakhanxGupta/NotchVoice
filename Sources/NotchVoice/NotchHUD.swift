import AppKit

/// A Dynamic-Island-style pill that slides down from the notch.
///
/// Signature element: a five-bar waveform driven by the *actual* microphone
/// level, so you can see your voice being heard before any words arrive.
/// On finish, the waveform collapses into a green check and the pill fades out.
final class NotchHUD {

    private var window: NSWindow?
    private var waveform: WaveformView?
    private var checkView: NSImageView?
    private var label: NSTextField?
    private var hideWorkItem: DispatchWorkItem?

    private let height: CGFloat = 42
    private let minWidth: CGFloat = 170
    private let maxWidth: CGFloat = 680
    private let hInset: CGFloat = 18
    private let leadingSlot: CGFloat = 26   // waveform / check area
    private let gap: CGFloat = 10

    /// SF Pro Rounded gives the pill a softer, more "island" personality
    /// than plain system type.
    private let labelFont: NSFont = {
        let base = NSFont.systemFont(ofSize: 14.5, weight: .medium)
        if let rounded = base.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: rounded, size: 14.5) {
            return font
        }
        return base
    }()

    // MARK: - Public API

    func show(text: String) {
        hideWorkItem?.cancel()
        ensureWindow()
        setLeading(recording: true)
        setText(text, placeholder: true)
        layout(for: text, animated: false)
        animateIn()
    }

    func update(text: String) {
        if window == nil || window?.isVisible == false { show(text: text); return }
        let isPlaceholder = text == "Listening…"
        setText(text, placeholder: isPlaceholder)
        layout(for: text, animated: true)
    }

    /// Feed the live mic level (RMS) into the waveform.
    func setLevel(_ level: Float) {
        waveform?.push(level: level)
    }

    /// Show the finished transcript with a "copied" affordance, then collapse.
    func showCopied(_ text: String) {
        ensureWindow()
        setLeading(recording: false)
        let shown = text.isEmpty ? "Copied" : text
        setText(shown, placeholder: false)
        layout(for: shown, animated: true)
        hide(after: 1.9)
    }

    func flashError(_ message: String) {
        hideWorkItem?.cancel()
        ensureWindow()
        setLeading(recording: false, symbol: "exclamationmark.triangle.fill",
                   color: .systemYellow)
        setText(message, placeholder: false)
        layout(for: message, animated: false)
        animateIn()
        hide(after: 2.6)
    }

    func hide(after delay: TimeInterval) {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.animateOut() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Content states

    private func setText(_ text: String, placeholder: Bool) {
        label?.stringValue = text
        label?.textColor = placeholder
            ? NSColor.white.withAlphaComponent(0.45)
            : NSColor.white.withAlphaComponent(0.95)
    }

    private func setLeading(recording: Bool,
                            symbol: String = "checkmark.circle.fill",
                            color: NSColor = .systemGreen) {
        waveform?.isHidden = !recording
        checkView?.isHidden = recording
        if recording {
            waveform?.start()
        } else {
            waveform?.stop()
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            checkView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            checkView?.contentTintColor = color
            // Small pop when the check lands.
            if let layer = checkView?.layer {
                let pop = CASpringAnimation(keyPath: "transform.scale")
                pop.fromValue = 0.4
                pop.toValue = 1.0
                pop.damping = 12
                pop.initialVelocity = 8
                pop.duration = pop.settlingDuration
                layer.add(pop, forKey: "pop")
            }
        }
    }

    // MARK: - Animations

    private func animateIn() {
        guard let window, let screen = NSScreen.main else { return }
        let target = frameRect(width: window.frame.width, screen: screen)
        var start = target
        start.origin.y += 14
        window.setFrame(start, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            ctx.allowsImplicitAnimation = true
            window.animator().alphaValue = 1
            window.animator().setFrame(target, display: true)
        }
    }

    private func animateOut() {
        guard let window else { return }
        var end = window.frame
        end.origin.y += 14
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            window.animator().setFrame(end, display: true)
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.waveform?.stop()
        })
    }

    // MARK: - Layout

    private func layout(for text: String, animated: Bool) {
        guard let window, let screen = NSScreen.main else { return }
        let textWidth = (text as NSString)
            .size(withAttributes: [.font: labelFont]).width
        let contentWidth = leadingSlot + gap + ceil(textWidth)
        let width = min(max(minWidth, contentWidth + hInset * 2), maxWidth)
        let target = frameRect(width: width, screen: screen)

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
                window.animator().setFrame(target, display: true)
            }
        } else {
            window.setFrame(target, display: true)
        }
    }

    private func frameRect(width: CGFloat, screen: NSScreen) -> NSRect {
        let f = screen.frame
        let x = f.midX - width / 2
        // On notched Macs safeAreaInsets.top == the notch height; otherwise fall
        // back to the menu-bar thickness. Sit the pill fully *below* that so the
        // physical notch never covers it.
        let topInset = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let y = f.maxY - topInset - height - 4
        return NSRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Window

    private func ensureWindow() {
        guard window == nil else { return }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: minWidth, height: height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        // Above normal app windows *and* fullscreen apps. `.statusBar` (25) is
        // beaten by fullscreen video/windows in their own Space; the overlay
        // level plus the space-joining behaviors below let the pill float over
        // everything.
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.hasShadow = true

        let pill = NSView(frame: win.contentView!.bounds)
        pill.autoresizingMask = [.width, .height]
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.cgColor
        pill.layer?.cornerRadius = height / 2
        pill.layer?.cornerCurve = .continuous
        pill.layer?.masksToBounds = true
        // Hairline edge so the pill reads against dark wallpapers.
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = NSColor.white.withAlphaComponent(0.09).cgColor

        let wave = WaveformView()
        wave.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(wave)

        let check = NSImageView()
        check.translatesAutoresizingMaskIntoConstraints = false
        check.wantsLayer = true
        check.imageScaling = .scaleProportionallyUpOrDown
        check.isHidden = true
        pill.addSubview(check)

        let text = NSTextField(labelWithString: "")
        text.font = labelFont
        text.textColor = .white
        text.backgroundColor = .clear
        text.drawsBackground = false
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(text)

        NSLayoutConstraint.activate([
            wave.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: hInset),
            wave.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            wave.widthAnchor.constraint(equalToConstant: leadingSlot),
            wave.heightAnchor.constraint(equalToConstant: 22),

            check.centerXAnchor.constraint(equalTo: wave.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 19),
            check.heightAnchor.constraint(equalToConstant: 19),

            text.leadingAnchor.constraint(equalTo: wave.trailingAnchor, constant: gap),
            text.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -hInset),
            text.centerYAnchor.constraint(equalTo: pill.centerYAnchor)
        ])

        win.contentView = pill
        window = win
        waveform = wave
        checkView = check
        label = text
    }
}

// MARK: - WaveformView

/// Five rounded bars whose heights follow the live microphone level.
/// Center bars respond more than edge bars, like a real level meter.
private final class WaveformView: NSView {

    private var bars: [CALayer] = []
    private let barCount = 5
    private let barWidth: CGFloat = 3.5
    private let barGap: CGFloat = 2.5
    private let minBarHeight: CGFloat = 4
    private let maxBarHeight: CGFloat = 20
    /// How strongly each bar tracks the level (center-weighted).
    private let sensitivity: [CGFloat] = [0.55, 0.85, 1.0, 0.85, 0.55]
    private var smoothed: Float = 0
    private var idleTimer: Timer?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<barCount {
            let bar = CALayer()
            bar.backgroundColor = NSColor.systemRed.cgColor
            bar.cornerRadius = barWidth / 2
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
        let startX = (bounds.width - totalWidth) / 2
        for (i, bar) in bars.enumerated() {
            let x = startX + CGFloat(i) * (barWidth + barGap)
            let h = bar.frame.height == 0 ? minBarHeight : bar.frame.height
            bar.frame = NSRect(x: x, y: (bounds.height - h) / 2, width: barWidth, height: h)
        }
    }

    /// Gentle idle shimmer so the bars breathe even in silence.
    func start() {
        stop()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            self?.render()
        }
    }

    func stop() {
        idleTimer?.invalidate()
        idleTimer = nil
        smoothed = 0
    }

    func push(level: Float) {
        // Fast attack, slow release — feels responsive without flickering.
        smoothed = level > smoothed ? level : smoothed * 0.82 + level * 0.18
    }

    private func render() {
        // Speech RMS is small (~0.02–0.2); scale it into 0…1.
        let norm = min(1, CGFloat(smoothed) * 9)
        smoothed *= 0.9   // decay between buffers so silence settles down
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.1)
        for (i, bar) in bars.enumerated() {
            let jitter = CGFloat.random(in: 0.85...1.1)
            let h = max(minBarHeight,
                        min(maxBarHeight,
                            minBarHeight + (maxBarHeight - minBarHeight) * norm * sensitivity[i] * jitter))
            let x = bar.frame.origin.x
            bar.frame = NSRect(x: x, y: (bounds.height - h) / 2, width: barWidth, height: h)
        }
        CATransaction.commit()
    }
}
