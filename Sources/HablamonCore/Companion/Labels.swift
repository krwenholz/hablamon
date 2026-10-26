/// Every fixed piece of text in the window. Spanish is the default; holding the English hotkey
/// shows English.
public enum LabelKey: CaseIterable, Sendable {
    case idle, reading, speaking, phoneInUse, findingTV, lostCamera, needsYou
    case conversation, words, knowIt
    case camera, tv, box, text, voice
    case narrator
    case male, female, neutral
    case repeatLine, slow, pause, recalibrate
    case diagnostics
    case gapPaused, gapLost, gapScreen
    case glossHint
}

public func text(_ label: LabelKey, english: Bool) -> String {
    let (es, en): (String, String) =
        switch label {
        case .idle: ("En espera", "Idle")
        case .reading: ("Leyendo", "Reading")
        case .speaking: ("Hablando", "Speaking")
        case .phoneInUse: ("Móvil en uso", "Phone in use")
        case .findingTV: ("Buscando la tele", "Finding TV")
        case .lostCamera: ("Cámara perdida", "Lost camera")
        case .needsYou: ("Te necesito", "Needs you")
        case .conversation: ("Conversación", "Conversation")
        case .words: ("Palabras", "Words")
        case .knowIt: ("Ya la sé", "I know it")
        case .camera: ("Cámara", "Camera")
        case .tv: ("Tele", "TV")
        case .box: ("Caja", "Box")
        case .text: ("Texto", "Text")
        case .voice: ("Voz", "Voice")
        case .narrator: ("Narrador", "Narrator")
        case .male: ("Masculina", "Male")
        case .female: ("Femenina", "Female")
        case .neutral: ("Neutra", "Neutral")
        case .repeatLine: ("Repetir", "Repeat")
        case .slow: ("Lento", "Slow")
        case .pause: ("Pausa", "Pause")
        case .recalibrate: ("Recalibrar", "Recalibrate")
        case .diagnostics: ("Diagnóstico", "Diagnostics")
        case .gapPaused: ("Móvil en uso", "Phone in use")
        case .gapLost: ("Cámara perdida", "Camera lost")
        case .gapScreen: ("Tele perdida", "TV lost")
        case .glossHint: ("Sin significado en el glosario", "No meaning in the glossary")
        }
    return english ? en : es
}

public func text(_ pill: StatusPill, english: Bool) -> String {
    let label: LabelKey =
        switch pill {
        case .idle: .idle
        case .reading: .reading
        case .speaking: .speaking
        case .phoneInUse: .phoneInUse
        case .findingTV: .findingTV
        case .lostCamera: .lostCamera
        case .needsYou: .needsYou
        }
    return text(label, english: english)
}

/// "2 voces sin asignar", with the noun agreeing with the count.
public func unassignedVoices(_ count: Int, english: Bool) -> String {
    if english { return count == 1 ? "1 unassigned voice" : "\(count) unassigned voices" }
    return count == 1 ? "1 voz sin asignar" : "\(count) voces sin asignar"
}
