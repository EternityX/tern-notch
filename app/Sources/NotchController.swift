import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class HoverView: NSView {
    var onPointer: (() -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { onPointer?() }
    override func mouseExited(with event: NSEvent) { onPointer?() }
    override func mouseMoved(with event: NSEvent) { onPointer?() }
}

struct NotchGeometry: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat

    static let wing: CGFloat = 76
    static let ear: CGFloat = 8
    static let canvasWidth: CGFloat = 700

    var collapsedSize: CGSize {
        CGSize(width: notchWidth + 2 * Self.wing + 2 * Self.ear, height: notchHeight)
    }

    var compactSize: CGSize {
        CGSize(width: notchWidth + 2 * Self.ear, height: notchHeight)
    }
}

@MainActor
final class NotchUI: ObservableObject {
    @Published var expanded = false
    @Published var peeking = false
    @Published var geometry = NotchGeometry(notchWidth: 190, notchHeight: 32)
    @Published var maxHeight: CGFloat = 640
    @Published var footerHeight: CGFloat = 160
    @Published var tabsHeight: CGFloat = 36
    var canvasHeight: CGFloat { maxHeight + 60 }
    var holdOpen = false {
        didSet { if oldValue && !holdOpen { holdReleased() } }
    }
    var menuOpen = false {
        didSet { if oldValue && !menuOpen { holdReleased() } }
    }
    var keepOpen: Bool { holdOpen || menuOpen }
    var requestCollapse: () -> Void = {}
    var requestExpand: () -> Void = {}
    var holdReleased: () -> Void = {}
}

@MainActor
final class NotchController {
    private let store: Store
    private let ui = NotchUI()
    private let panel: NotchPanel
    private var centerX: CGFloat = 0
    private var topY: CGFloat = 0
    private var shapeSize: CGSize = .zero
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var hostHeight: NSLayoutConstraint?
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var mouseMonitors: [Any] = []
    private var openedAt = Date.distantPast

    init(store: Store) {
        self.store = store
        panel = NotchPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        applyCollectionBehavior()
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let hover = HoverView()
        let root = NotchRoot(store: store, ui: ui) { [weak self] size in self?.shapeSized(size) }
        let host = FirstMouseHostingView(rootView: root)
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        hover.addSubview(host)
        let height = host.heightAnchor.constraint(equalToConstant: ui.canvasHeight)
        hostHeight = height
        NSLayoutConstraint.activate([
            host.centerXAnchor.constraint(equalTo: hover.centerXAnchor),
            host.topAnchor.constraint(equalTo: hover.topAnchor),
            host.widthAnchor.constraint(equalToConstant: NotchGeometry.canvasWidth),
            height,
        ])
        panel.contentView = hover
        hover.onPointer = { [weak self] in self?.pointerMoved() }
        ui.requestCollapse = { [weak self] in self?.collapse() }
        ui.requestExpand = { [weak self] in self?.expand() }
        ui.holdReleased = { [weak self] in self?.pointerMoved() }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { mouseMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { mouseMonitors.append(local) }

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.placeOnScreen() } })
        observers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.pointerInside, !self.ui.menuOpen else { return }
                self.collapse()
            }
        })
        observers.append(center.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.ui.menuOpen = true } })
        observers.append(center.addObserver(
            forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.ui.menuOpen = false } })

        store.$visible
            .removeDuplicates()
            .sink { [weak self] visible in self?.setVisible(visible) }
            .store(in: &cancellables)

        store.$state
            .map { Set(($0?.agents ?? []).filter(\.needsInput).map(\.pane)) }
            .removeDuplicates()
            .scan((Set<Int>(), Set<Int>())) { last, now in (last.1, now) }
            .sink { [weak self] previous, now in
                let fresh = now.subtracting(previous)
                guard !fresh.isEmpty else { return }
                if Preferences.shared.soundOnAsk { NSSound(named: "Glass")?.play() }
                guard let self, !self.ui.holdOpen else { return }
                let asking = self.store.agents.first { fresh.contains($0.pane) }
                if let asking { withAnimation(Motion.content) { self.store.selectedPane = asking.pane } }
            }
            .store(in: &cancellables)

        let prefs = Preferences.shared
        prefs.$display.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.placeOnScreen() }
        }.store(in: &cancellables)
        prefs.$overFullScreen.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyCollectionBehavior() }
        }.store(in: &cancellables)

        placeOnScreen()
        panel.orderFrontRegardless()
    }

    private func applyCollectionBehavior() {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if Preferences.shared.overFullScreen { behavior.insert(.fullScreenAuxiliary) }
        panel.collectionBehavior = behavior
    }

    private func placeOnScreen() {
        let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
        let preferred = Preferences.shared.display == .notch ? notched : NSScreen.screens.first
        guard let screen = preferred ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = screen.frame.width - left.width - right.width
            ui.geometry = NotchGeometry(notchWidth: width, notchHeight: inset)
            centerX = screen.frame.minX + left.width + width / 2
        } else {
            let bar = max(screen.frame.maxY - screen.visibleFrame.maxY, NSStatusBar.system.thickness)
            ui.geometry = NotchGeometry(notchWidth: 180, notchHeight: bar)
            centerX = screen.frame.midX
        }
        topY = screen.frame.maxY
        ui.maxHeight = min(topY - screen.visibleFrame.minY - 12, 820)
        hostHeight?.constant = ui.canvasHeight
        let frame = NSRect(x: (centerX - NotchGeometry.canvasWidth / 2).rounded(), y: topY - ui.canvasHeight,
                           width: NotchGeometry.canvasWidth, height: ui.canvasHeight)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
        updateInteractivity()
    }

    private func shapeSized(_ size: CGSize) {
        shapeSize = size
        updateInteractivity()
    }

    private func setVisible(_ visible: Bool) {
        panel.alphaValue = visible ? 1 : 0
        if !visible { collapse() }
        updateInteractivity()
    }

    private func updateInteractivity() {
        let interactive = store.visible && (ui.expanded ? shapeRect : openRect).contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == interactive { panel.ignoresMouseEvents = !interactive }
    }

    private var shapeRect: NSRect {
        let size = shapeSize == .zero ? ui.geometry.compactSize : shapeSize
        return NSRect(x: centerX - size.width / 2, y: topY - size.height, width: size.width, height: size.height)
    }

    private var openRect: NSRect {
        let r = shapeRect
        return NSRect(x: r.minX, y: r.minY - 4, width: r.width, height: r.height + 8)
    }

    private var stayRect: NSRect { shapeRect.insetBy(dx: -16, dy: -16) }

    private var pointerInside: Bool {
        let point = NSEvent.mouseLocation
        return ui.expanded ? stayRect.contains(point) : openRect.contains(point)
    }

    private func pointerMoved() {
        updateInteractivity()
        if pointerInside {
            collapseWork?.cancel()
            collapseWork = nil
            if !ui.expanded, !ui.peeking { ui.peeking = true }
            guard !ui.expanded, expandWork == nil, Preferences.shared.openOn == .hover else { return }
            let delay = Preferences.shared.hoverDelay
            if delay <= 0.01 {
                expand()
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.expandWork = nil
                if self.pointerInside { self.expand() }
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            expandWork?.cancel()
            expandWork = nil
            if ui.peeking { ui.peeking = false }
            guard ui.expanded, !ui.keepOpen, collapseWork == nil else { return }
            let opening = 0.5 - Date().timeIntervalSince(openedAt)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.collapseWork = nil
                if !self.pointerInside && !self.ui.keepOpen { self.collapse() }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(Preferences.shared.closeDelay, opening), execute: work)
        }
    }

    private func expand() {
        guard !ui.expanded, store.visible else { return }
        expandWork?.cancel()
        expandWork = nil
        openedAt = Date()
        store.selectedPane = nil
        if Preferences.shared.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        withAnimation(Motion.open) {
            ui.peeking = false
            ui.expanded = true
        }
    }

    private func collapse() {
        collapseWork?.cancel()
        collapseWork = nil
        if panel.isKeyWindow {
            panel.makeFirstResponder(nil)
            if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
                front.activate()
            } else {
                NSApp.deactivate()
            }
        }
        if ui.expanded {
            withAnimation(Motion.close) { ui.expanded = false }
        }
        ui.holdOpen = false
    }
}
