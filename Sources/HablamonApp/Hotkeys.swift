#if canImport(Carbon)
    import AppKit
    import Carbon.HIToolbox
    import HablamonCore
    import HablamonModels

    /// Global hotkeys through Carbon's `RegisterEventHotKey`, which works while other apps are focused
    /// and needs no Accessibility permission. Handles key release too, for hold-to-show-English.
    @MainActor
    final class HotkeyCenter {
        struct Binding {
            var name: String
            var pressed: () -> Void
            var released: (() -> Void)?
        }

        private var bindings: [UInt32: Binding] = [:]
        private var references: [EventHotKeyRef] = []
        private var handler: EventHandlerRef?
        private var layoutObserver: NSObjectProtocol?
        private(set) var failures: [String] = []

        static let shared = HotkeyCenter()

        /// Registers `hotkey` (as written in settings.json). Bad or taken hotkeys are recorded in `failures`.
        func register(_ hotkey: String, pressed: @escaping () -> Void, released: (() -> Void)? = nil) {
            installHandlerIfNeeded()
            let id = UInt32(bindings.count + 1)
            bindings[id] = Binding(name: hotkey, pressed: pressed, released: released)
            if let failure = activate(id: id, hotkey: hotkey, layout: KeyboardLayout.current()) {
                failures.append(failure)
            }
        }

        /// Registers one hotkey with Carbon, finding its letter in `layout` (Dvorak's E is not QWERTY's).
        private func activate(id: UInt32, hotkey: String, layout: KeyboardLayout?) -> String? {
            guard let parsed = ParsedHotkey.parse(hotkey),
                let code = layout?.keyCode(for: parsed.key, command: parsed.command) ?? Self.keyCodes[parsed.key]
            else { return "hotkey \(hotkey): not understood" }
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(code), Self.modifiers(parsed), EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(), 0, &reference)
            guard status == noErr, let reference else { return "hotkey \(hotkey): already taken (\(status))" }
            references.append(reference)
            return nil
        }

        /// Switching keyboard layouts moves the letters, so register everything again.
        private func reregister() {
            for reference in references { UnregisterEventHotKey(reference) }
            references = []
            let layout = KeyboardLayout.current()
            let problems = bindings.sorted { $0.key < $1.key }.compactMap { id, binding in
                activate(id: id, hotkey: binding.name, layout: layout)
            }
            onEvent?("keyboard layout changed; hotkeys re-registered\(problems.isEmpty ? "" : ": \(problems)")")
        }

        /// Called with "pressed opt+cmd+E" and the like, for the session log.
        var onEvent: ((String) -> Void)?

        fileprivate func handle(id: UInt32, pressed: Bool) {
            guard let binding = bindings[id] else { return }
            onEvent?("hotkey \(pressed ? "pressed" : "released") \(binding.name)")
            if pressed { binding.pressed() } else { binding.released?() }
        }

        private func installHandlerIfNeeded() {
            guard handler == nil else { return }
            layoutObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { HotkeyCenter.shared.reregister() }
            }
            var types = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
            ]
            InstallEventHandler(GetApplicationEventTarget(), hotkeyCallback, 2, &types, nil, &handler)
        }

        nonisolated static let signature: OSType = 0x4842_4C4D  // "HBLM"

        static func modifiers(_ hotkey: ParsedHotkey) -> UInt32 {
            var flags = 0
            if hotkey.command { flags |= cmdKey }
            if hotkey.option { flags |= optionKey }
            if hotkey.shift { flags |= shiftKey }
            if hotkey.control { flags |= controlKey }
            return UInt32(flags)
        }

        /// QWERTY positions, the fallback when the current layout can't be read.
        static let keyCodes: [Character: Int] = [
            "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
            "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
            "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R,
            "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
            "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        ]
    }

    private func hotkeyCallback(_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
            MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard status == noErr, id.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
        let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
        let hotkeyID = id.id
        MainActor.assumeIsolated { HotkeyCenter.shared.handle(id: hotkeyID, pressed: pressed) }
        return noErr
    }

    extension AppModel {
        /// Binds every hotkey in settings.json to its action.
        func registerHotkeys() {
            let center = HotkeyCenter.shared
            center.onEvent = { [weak self] line in self?.note(line) }
            center.register(hotkeys.repeatLast) { [weak self] in self?.repeatLast(slow: false) }
            center.register(hotkeys.repeatLastSlowly) { [weak self] in self?.repeatLast(slow: true) }
            center.register(hotkeys.toggleSpeed) { [weak self] in self?.toggleSpeed() }
            center.register(hotkeys.togglePause) { [weak self] in self?.togglePause() }
            center.register(hotkeys.recalibrate) { [weak self] in self?.recalibrate() }
            center.register(
                hotkeys.holdForEnglish, pressed: { [weak self] in self?.english = true },
                released: { [weak self] in self?.english = false })
            issues += center.failures
            // While any app has secure keyboard input on (password fields, some terminals), macOS
            // doesn't deliver global hotkeys at all.
            if IsSecureEventInputEnabled() {
                note("secure keyboard input is on: hotkeys won't fire until the app that enabled it releases it")
            }
            note(
                "hotkeys registered; failures: \(center.failures.isEmpty ? "none" : center.failures.joined(separator: "; "))"
            )
        }
    }
#endif
