#if canImport(AppKit)
    import AppKit
    import HablamonCore

    extension AppModel {
        /// Handles the plain keys in settings.json while Hablamon is the front app. Keys with ⌘, ⌥,
        /// or ⌃ pass through so menu shortcuts keep working, and so does typing in a text field.
        func installKeyHandler() {
            let map = KeyMap(keys)
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self else { return event }
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if !modifiers.isDisjoint(with: [.command, .option, .control]) { return event }
                if NSApp.keyWindow?.firstResponder is NSText { return event }
                // Escape closes the whole-screen translation.
                if event.keyCode == 53, screenOpen {
                    if event.type == .keyDown { closeScreen() }
                    return nil
                }
                guard let characters = event.charactersIgnoringModifiers,
                    let command = map.command(for: characters, shift: modifiers.contains(.shift))
                else { return event }
                let down = event.type == .keyDown
                if command == .holdForEnglish {
                    if !event.isARepeat { english = down }
                } else if down && !event.isARepeat {
                    note("key \(command)")
                    perform(command)
                }
                return nil
            }
        }

        private func perform(_ command: KeyCommand) {
            switch command {
            case .repeatLast: repeatLast(slow: false)
            case .repeatLastSlowly: repeatLast(slow: true)
            case .toggleSpeed: toggleSpeed()
            case .togglePause: togglePause()
            case .recalibrate: recalibrate()
            case .holdForEnglish: break
            case .toggleCamera: toggleCamera()
            case .toggleRecap: showRecap.toggle()
            case .translateScreen: toggleScreenTranslation()
            }
        }
    }
#endif
