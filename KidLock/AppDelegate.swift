import Cocoa
import Carbon.HIToolbox

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State
    private var statusItem: NSStatusItem!
    private var isLocked: Bool = false {
        didSet { updateMenuTitle() }
    }

    // MARK: - Event Tap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - Fail-safe Auto Unlock
    private var autoUnlockTimer: Timer?
    private let autoUnlockSeconds: TimeInterval = 10 * 60   // 10 menit

    // MARK: - Unlock Combo (Ctrl + Option + Command + L)
    private let unlockKeyCode: CGKeyCode = 37 // 'L' (US layout). Jika layout JIS beda, bilang ya.
    private let unlockFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]

    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("✅ KidLock launched")

        setupStatusBar()
        installEventTap()

        // AUTO-LOCK saat app dibuka
        isLocked = true
        startAutoUnlockTimer() // optional: hapus baris ini kalau tidak mau auto-unlock
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeEventTap()
    }

    // MARK: - Status Bar UI
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.title = "KidLock"
        }

        let menu = NSMenu()

        // Item pertama akan kita ubah title-nya via updateMenuTitle()
        let toggleItem = NSMenuItem(title: "Lock Input", action: #selector(toggleLock), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Manual unlock (kalau kamu pengin dari menu)
        let forceUnlockItem = NSMenuItem(title: "Force Unlock (Menu)", action: #selector(forceUnlock), keyEquivalent: "")
        forceUnlockItem.target = self
        menu.addItem(forceUnlockItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit KidLock", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateMenuTitle()
        NSLog("✅ Status bar item created")
    }

    private func updateMenuTitle() {
        guard let menu = statusItem.menu, let toggleItem = menu.items.first else { return }
        toggleItem.title = isLocked ? "Unlock Input" : "Lock Input"
        statusItem.button?.title = isLocked ? "KidLock 🔒" : "KidLock"
    }

    // MARK: - Actions
    @objc private func toggleLock() {
        isLocked.toggle()

        if isLocked {
            startAutoUnlockTimer()
        } else {
            stopAutoUnlockTimer()
        }

        NSLog(isLocked ? "🔒 LOCKED" : "🔓 UNLOCKED")
    }

    @objc private func forceUnlock() {
        isLocked = false
        stopAutoUnlockTimer()
        NSLog("🔓 Force unlocked from menu")
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Auto Unlock
    private func startAutoUnlockTimer() {
        stopAutoUnlockTimer()
        autoUnlockTimer = Timer.scheduledTimer(withTimeInterval: autoUnlockSeconds, repeats: false) { [weak self] _ in
            self?.isLocked = false
            NSLog("⏱️ Auto-unlock triggered")
        }
    }

    private func stopAutoUnlockTimer() {
        autoUnlockTimer?.invalidate()
        autoUnlockTimer = nil
    }

    // MARK: - Event Tap Helpers
    private func mask(for types: [CGEventType]) -> CGEventMask {
        return types.reduce(CGEventMask(0)) { partial, t in
            partial | (CGEventMask(1) << CGEventMask(t.rawValue))
        }
    }

    // MARK: - Event Tap Install/Remove
    private func installEventTap() {
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,

            .otherMouseDown, .otherMouseUp,
            .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel
        ]

        let eventMask = mask(for: types)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            let mySelf = Unmanaged<AppDelegate>.fromOpaque(refcon!).takeUnretainedValue()

            // Jika event tap dinonaktifkan sistem, nyalakan lagi
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = mySelf.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                    NSLog("⚠️ Event tap re-enabled (was disabled)")
                }
                return Unmanaged.passUnretained(event)
            }

            // Kalau tidak terkunci, biarkan event lewat normal
            if !mySelf.isLocked {
                return Unmanaged.passUnretained(event)
            }

            // Saat terkunci: cek combo unlock
            if type == .keyDown {
                let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags

                if keyCode == mySelf.unlockKeyCode && flags.contains(mySelf.unlockFlags) {
                    mySelf.isLocked = false
                    mySelf.stopAutoUnlockTimer()
                    NSLog("🔓 Unlocked by shortcut")
                    // Telan event unlock juga
                    return nil
                }
            }

            // Selain combo unlock: telan semua input
            return nil
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        guard let eventTap else {
            NSLog("❌ Failed to create event tap. Enable Accessibility/Input Monitoring for KidLock.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        NSLog("✅ Event tap installed & enabled")
    }

    private func removeEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        NSLog("🧹 Event tap removed")
    }
}
