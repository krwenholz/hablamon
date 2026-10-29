import Testing

@testable import HablamonCore

/// Expected strings follow espeak-ng's Spanish (the phonemizer Kokoro was trained on), with
/// Latin American seseo (`c`/`z` → s) and yeísmo (`ll` → ʝ).
struct SpanishPhonemesTests {
    @Test(arguments: [
        ("casa", "kˈasa"),
        ("ciudad", "sjuðˈad"),
        ("poción", "posjˈon"),
        ("cruzado", "kɾusˈaðo"),
        ("bolsillo", "bolsˈiʝo"),
        ("Miguel", "miɣˈel"),
        ("guardas", "ɡwˈaɾðas"),
        ("pingüino", "piŋɡwˈino"),
        ("quieras", "kjˈeɾas"),
        ("día", "dˈia"),
        ("muy", "mˈuj"),
        ("hoy", "ˈoj"),
        ("ayudar", "aʝuðˈaɾ"),
        ("Meseta", "mesˈeta"),
        ("rápido", "rˈapiðo"),
        ("perro", "pˈero"),
        ("Pokémon", "pokˈemon"),
        ("chico", "ʧˈiko"),
        ("niño", "nˈiɲo"),
        ("gente", "xˈente"),
        ("examen", "eksˈamen"),
    ])
    func word(_ text: String, _ expected: String) {
        #expect(SpanishPhonemes.phonemize(text) == expected)
    }

    @Test func functionWordsStayUnstressed() {
        #expect(SpanishPhonemes.phonemize("a los que se me de") == "a los ke se me ðe")
    }

    @Test func softensBDGBetweenSoundsAcrossWords() {
        #expect(SpanishPhonemes.phonemize("muy bien") == "mˈuj βjˈen")
        #expect(SpanishPhonemes.phonemize("con dos") == "kon dˈos")
        #expect(SpanishPhonemes.phonemize("los demás") == "los ðemˈas")
        #expect(SpanishPhonemes.phonemize("Bien. Dos") == "bjˈen. dˈos")
    }

    @Test func keepsPunctuationThatShapesProsody() {
        #expect(SpanishPhonemes.phonemize("¡Ah! ¿Sí? Bueno...") == "ˈa! sˈi? bwˈeno…")
    }

    @Test func spellsOutNumbers() {
        #expect(SpanishPhonemes.phonemize("2 miembros") == "dˈos mjˈembɾos")
    }

    @Test func sentence() {
        let text = "Está muy bien que quieras ayudar, pero no puedes meterte en líos ya en tu primer día."
        #expect(
            SpanishPhonemes.phonemize(text)
                == "estˈa mˈuj βjˈen ke kjˈeɾas aʝuðˈaɾ, pˈeɾo nˈo pwˈeðes metˈeɾte en lˈios ʝˈa en tu pɾimˈeɾ ðˈia."
        )
    }

    @Test func splitsLongPhonemeStringsAtPausesThenSpaces() {
        let pieces = SpanishPhonemes.pieces("ab cd, ef gh ij", maxLength: 8)
        #expect(pieces == ["ab cd,", "ef gh ij"])
        #expect(SpanishPhonemes.pieces("abc def ghi", maxLength: 7) == ["abc def", "ghi"])
        #expect(SpanishPhonemes.pieces("short", maxLength: 56) == ["short"])
        // Balanced rather than greedy, so a name isn't left on its own at the end.
        #expect(SpanishPhonemes.pieces("aa bb cc dd ee", maxLength: 12) == ["aa bb cc", "dd ee"])
    }
}
