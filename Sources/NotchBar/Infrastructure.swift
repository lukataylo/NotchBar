import AppKit
import SwiftUI
import Combine
import Carbon.HIToolbox
import ApplicationServices
import os.log

private let log = Logger(subsystem: "com.notchbar", category: "infra")

// MARK: - Key-Accepting Panel

class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Panel Controller (one per screen)

class NotchPanelController {
    let panel: NSPanel

    init(screen: NSScreen, state: NotchState) {
        let size = NSSize(width: 420, height: 600)
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - size.height

        panel = KeyablePanel(
            contentRect: NSRect(x: x, y: y, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar + 1
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let view = NotchView(state: state, screenID: screen.displayID, hasNotch: screen.hasNotch)
        let hosting = NSHostingView(rootView: view)
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.orderFrontRegardless()
    }

    func teardown() { panel.orderOut(nil) }
}

// MARK: - Screen Manager

class MultiScreenManager {
    var controllers: [CGDirectDisplayID: NotchPanelController] = [:]
    let state: NotchState
    var clickMonitor: Any?

    init(state: NotchState) { self.state = state }

    func setup() {
        refreshScreens()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refreshScreens() }

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            guard let self = self, self.state.expandedScreenID != nil else { return }
            if !self.controllers.values.contains(where: { $0.panel.frame.contains(NSEvent.mouseLocation) }) {
                DispatchQueue.main.async { self.state.expandedScreenID = nil }
            }
        }
    }

    func refreshScreens() {
        let current = Set(NSScreen.screens.map { $0.displayID })
        for id in Set(controllers.keys).subtracting(current) {
            controllers[id]?.teardown(); controllers.removeValue(forKey: id)
        }
        for screen in NSScreen.screens where controllers[screen.displayID] == nil {
            controllers[screen.displayID] = NotchPanelController(screen: screen, state: state)
        }
    }
}

// MARK: - Hotkey Manager: Cmd+Shift+C, Cmd+Shift+Y, Cmd+Shift+N

class HotkeyManager {
    // Stored strongly to keep handlers alive for app lifetime
    private var handlerMap: HotkeyHandlerMap

    init(state: NotchState) {
        handlerMap = HotkeyHandlerMap()

        // Register all hotkeys with their IDs
        handlerMap.handlers[1] = {
            log.info("Hotkey: Cmd+Shift+C (toggle)")
            if state.expandedScreenID != nil { state.expandedScreenID = nil }
            else {
                let loc = NSEvent.mouseLocation
                state.expandedScreenID = (NSScreen.screens.first { $0.frame.contains(loc) } ?? NSScreen.main)?.displayID
            }
        }

        handlerMap.handlers[2] = {
            guard let session = state.activeSession, let approval = session.pendingApproval else { return }
            log.info("Hotkey: Cmd+Shift+Y (approve \(approval.requestId))")
            ProviderManager.shared?.approve(requestId: approval.requestId, session: session)
        }

        handlerMap.handlers[3] = {
            guard let session = state.activeSession, let approval = session.pendingApproval else { return }
            log.info("Hotkey: Cmd+Shift+N (reject \(approval.requestId))")
            ProviderManager.shared?.reject(requestId: approval.requestId, session: session)
        }

        // Register Carbon hotkeys — all use Cmd+Shift to avoid conflicts with standard app shortcuts
        var ref1: EventHotKeyRef?
        var ref2: EventHotKeyRef?
        var ref3: EventHotKeyRef?
        let sig = OSType(0x4E434C44)
        let cmdShift = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_C), cmdShift, EventHotKeyID(signature: sig, id: 1), GetApplicationEventTarget(), 0, &ref1)
        RegisterEventHotKey(UInt32(kVK_ANSI_Y), cmdShift, EventHotKeyID(signature: sig, id: 2), GetApplicationEventTarget(), 0, &ref2)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), cmdShift, EventHotKeyID(signature: sig, id: 3), GetApplicationEventTarget(), 0, &ref3)

        // Single event handler dispatches by hotkey ID
        let mapPtr = Unmanaged.passUnretained(handlerMap).toOpaque()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }

            var hotkeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                            nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)

            let map = Unmanaged<HotkeyHandlerMap>.fromOpaque(userData).takeUnretainedValue()
            if let handler = map.handlers[hotkeyID.id] {
                DispatchQueue.main.async { handler() }
            }
            return noErr
        }, 1, &eventType, mapPtr, nil)

        log.info("Hotkeys registered: Cmd+Shift+C, Cmd+Shift+Y, Cmd+Shift+N")
    }
}

private class HotkeyHandlerMap {
    var handlers: [UInt32: () -> Void] = [:]
}

// MARK: - Menu Bar Icon

class StatusItemManager: NSObject {
    var statusItem: NSStatusItem!
    let state: NotchState

    init(state: NotchState) {
        self.state = state
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                let path = NSBezierPath()
                let s = rect.width / 24.0
                let pts: [(CGFloat, CGFloat)] = [
                    (3,5),(20.998,5),(20.998,10.949),(24,10.949),(24,14.051),
                    (21,14.051),(21,17.079),(3,17.079),(3,14.05),(0,14.05),(0,10.95),(3,10.95)
                ]
                path.move(to: NSPoint(x: pts[0].0 * s, y: rect.height - pts[0].1 * s))
                for pt in pts.dropFirst() { path.line(to: NSPoint(x: pt.0 * s, y: rect.height - pt.1 * s)) }
                path.close(); NSColor.black.setFill(); path.fill()
                return true
            }
            img.isTemplate = true
            button.image = img
        }
        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Toggle Panel", action: #selector(toggle), keyEquivalent: "")
        toggleItem.image = NSImage(systemSymbolName: "rectangle.expand.vertical", accessibilityDescription: nil)
        toggleItem.keyEquivalentModifierMask = [.command, .shift]
        toggleItem.keyEquivalent = "c"
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let installItem = NSMenuItem(title: "Install Provider Integration", action: #selector(installHooks), keyEquivalent: "")
        installItem.image = NSImage(systemSymbolName: "link.badge.plus", accessibilityDescription: nil)
        installItem.target = self
        menu.addItem(installItem)

        let removeItem = NSMenuItem(title: "Remove Provider Integration", action: #selector(removeHooks), keyEquivalent: "")
        removeItem.image = NSImage(systemSymbolName: "link.badge.minus", accessibilityDescription: nil)
        removeItem.target = self
        menu.addItem(removeItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    var settingsWindow: NSWindow?

    @objc func toggle() {
        if state.expandedScreenID != nil { state.expandedScreenID = nil }
        else {
            let loc = NSEvent.mouseLocation
            state.expandedScreenID = (NSScreen.screens.first { $0.frame.contains(loc) } ?? NSScreen.main)?.displayID
        }
    }
    @objc func installHooks() {
        let provider = ProviderManager.shared?.activeProviderDescriptor(for: state.activeSession) ?? ProviderCatalog.claude
        let ok = ProviderManager.shared?.installIntegration(for: state.activeSession) ?? false
        let alert = NSAlert()
        if ok {
            alert.messageText = "Integration Installed"
            alert.informativeText = successMessage(for: provider)
        } else {
            alert.alertStyle = .warning
            alert.messageText = "Integration Problem"
            alert.informativeText = "Could not install \(provider.integrationTitle.lowercased()) for \(provider.displayName).\n\nCheck permissions for \(provider.settingsPath ?? "the provider configuration") and try again."
        }
        alert.runModal()
    }
    @objc func removeHooks() {
        let provider = ProviderManager.shared?.activeProviderDescriptor(for: state.activeSession) ?? ProviderCatalog.claude
        let ok = ProviderManager.shared?.removeIntegration(for: state.activeSession) ?? false
        let alert = NSAlert()
        if ok {
            alert.messageText = "Integration Removed"
            alert.informativeText = "\(provider.integrationTitle.capitalized) removed. Other \(provider.displayName) settings were preserved when possible."
        } else {
            alert.alertStyle = .warning
            alert.messageText = "Could Not Remove Integration"
            alert.informativeText = "Failed to update \(provider.settingsPath ?? "the provider configuration"). Check file permissions."
        }
        alert.runModal()
    }
    @objc func openSettings() {
        if let w = settingsWindow, w.isVisible { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        w.title = "NotchBar Settings"
        w.contentView = NSHostingView(rootView: SettingsView())
        w.center()
        w.makeKeyAndOrderFront(nil)
        settingsWindow = w
    }
    @objc func quit() { NSApp.terminate(nil) }

    private func successMessage(for provider: ProviderDescriptor) -> String {
        switch provider.id {
        case .claude:
            return "Claude Code will now stream live hook events and approval requests to NotchBar."
        case .codex:
            return "The managed Codex `notchbar` profile is installed. Resume with `codex -p notchbar resume` for the recommended monitored setup."
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var screenManager: MultiScreenManager!
    var hotkeyManager: HotkeyManager!
    var statusItemManager: StatusItemManager!
    var providerManager: ProviderManager!
    var onboardingWindow: NSWindow?
    let state = NotchState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prevent macOS from auto-terminating this background app
        ProcessInfo.processInfo.disableAutomaticTermination("NotchBar must stay alive to handle hook events")
        ProcessInfo.processInfo.disableSuddenTermination()

        log.info("NotchBar launching...")
        log.info("Screens: \(NSScreen.screens.count), notched: \(NSScreen.screens.filter { $0.hasNotch }.count)")

        screenManager = MultiScreenManager(state: state)
        screenManager.setup()
        hotkeyManager = HotkeyManager(state: state)
        statusItemManager = StatusItemManager(state: state)
        providerManager = ProviderManager(state: state)
        providerManager.start()

        UpdateChecker.shared.startChecking()

        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            log.info("First launch, showing onboarding")
            showOnboarding()
        }

        log.info("NotchBar launch complete")
    }

    func showOnboarding() {
        let onboardingView = OnboardingView { [weak self] in
            guard let self = self, let w = self.onboardingWindow else { return }
            log.info("Onboarding completed, closing window")
            // Order out first (no animation), then nil after a delay
            // to avoid crash from deallocating during AppKit animation
            w.orderOut(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.onboardingWindow = nil
            }
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        w.titlebarAppearsTransparent = true
        w.title = ""
        w.contentView = NSHostingView(rootView: onboardingView)
        w.center()

        // Temporarily activate the app so the window appears in front
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        onboardingWindow = w
    }

    func applicationWillTerminate(_ notification: Notification) {
        providerManager?.cleanup()
    }
}
