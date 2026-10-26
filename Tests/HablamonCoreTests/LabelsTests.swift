import Testing

@testable import HablamonCore

@Suite struct LabelsTests {
    @Test func everyLabelHasBothLanguages() {
        for label in LabelKey.allCases {
            let spanish = text(label, english: false)
            let english = text(label, english: true)
            #expect(!spanish.isEmpty && !english.isEmpty, "\(label)")
            #expect(spanish != english, "\(label) should differ between languages")
        }
    }

    @Test func pillsUseLabelTable() {
        #expect(text(StatusPill.speaking, english: false) == "Hablando")
        #expect(text(StatusPill.phoneInUse, english: true) == "Phone in use")
        for pill in StatusPill.allCases { #expect(!text(pill, english: false).isEmpty) }
    }

    @Test func knowItCopy() {
        #expect(text(.knowIt, english: false) == "Ya la sé")
    }
}
