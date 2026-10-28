#if canImport(SwiftUI)
    import HablamonCore
    import SwiftUI

    /// Ranked words from recent lines, each with its meaning, the sentence it came from, and
    /// a "Ya la sé" button that hides it for good.
    struct WordsPanel: View {
        var words: [VocabEntry]
        var english: Bool
        var onKnown: (String) -> Void

        var body: some View {
            InkCard(title: text(.words, english: english), detail: nil) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                            WordCard(word: word, english: english, onKnown: onKnown)
                            if index < words.count - 1 {
                                Rectangle().fill(Color(hex: 0xE6E3D6)).frame(height: 2)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                }
            }
        }
    }

    /// Definitions for the key words of the line on screen, two columns.
    struct KeyWordsPanel: View {
        var words: [VocabEntry]
        var english: Bool
        var onKnown: (String) -> Void

        var body: some View {
            InkCard(title: text(.wordsInLine, english: english), detail: nil) {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 28), GridItem(.flexible(), spacing: 28)], spacing: 4
                ) {
                    ForEach(words) { word in
                        WordCard(word: word, english: english, showsSentence: false, large: true, onKnown: onKnown)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }
        }
    }

    struct WordCard: View {
        var word: VocabEntry
        var english: Bool
        var showsSentence = true
        var large = false
        var onKnown: (String) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(word.lemma).font(Theme.dialogue(large ? 28 : 23, bold: true)).foregroundStyle(Theme.ink)
                    Text(classBadge)
                        .font(Theme.menu(11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.scarlet))
                    Spacer()
                    Button(text(.knowIt, english: english)) { onKnown(word.lemma) }
                        .buttonStyle(.plain)
                        .font(Theme.menu(12))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().stroke(Theme.ink, lineWidth: 2))
                }
                Text(word.gloss ?? text(.glossHint, english: english))
                    .font(Theme.menu(large ? 18 : 15, heavy: false))
                    .foregroundStyle(word.gloss == nil ? Theme.muted : Color(hex: 0x45444C))
                if showsSentence {
                    Text(context).font(Theme.dialogue(13)).foregroundStyle(Color(hex: 0x8A8892)).lineLimit(1)
                }
            }
            .padding(.vertical, 10)
        }

        private var classBadge: String {
            switch word.wordClass {
            case .noun: english ? "n." : "sust."
            case .verb: english ? "v." : "verbo"
            case .adjective: "adj."
            case .adverb: "adv."
            case .other: ""
            }
        }

        /// The source sentence with the word highlighted.
        private var context: AttributedString {
            var sentence = AttributedString(word.sentence)
            if let range = sentence.range(of: word.surface) {
                sentence[range].backgroundColor = Color(hex: 0xFFF2A8)
                sentence[range].foregroundColor = Theme.ink
            }
            return sentence
        }
    }
#endif
