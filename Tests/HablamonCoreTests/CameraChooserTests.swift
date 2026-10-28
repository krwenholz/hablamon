import Testing

@testable import HablamonCore

@Suite struct CameraChooserTests {
    let iphone = CameraInfo(id: "iphone-1", name: "iPhone de Kyle", kind: .continuity)
    let other = CameraInfo(id: "iphone-2", name: "Otro iPhone", kind: .continuity)
    let builtIn = CameraInfo(id: "facetime", name: "FaceTime HD Camera", kind: .builtIn)

    @Test func prefersPinnedDevice() {
        #expect(CameraChooser.choose(from: [iphone, other], pinned: "iphone-2", allowBuiltIn: false) == other)
    }

    @Test func firstContinuityWhenNothingPinned() {
        #expect(CameraChooser.choose(from: [builtIn, iphone], pinned: nil, allowBuiltIn: false) == iphone)
    }

    @Test func neverPicksBuiltInByDefault() {
        #expect(CameraChooser.choose(from: [builtIn], pinned: nil, allowBuiltIn: false) == nil)
    }

    @Test func builtInWhenAllowed() {
        #expect(CameraChooser.choose(from: [builtIn], pinned: nil, allowBuiltIn: true) == builtIn)
    }

    @Test func pinnedMissingDoesNotSwitch() {
        #expect(CameraChooser.choose(from: [other, builtIn], pinned: "iphone-1", allowBuiltIn: true) == nil)
    }

    @Test func macModePicksTheBuiltInCamera() {
        #expect(
            CameraChooser.choose(from: [iphone, builtIn], source: .mac, pinned: nil, allowBuiltIn: false) == builtIn)
    }

    @Test func macModeWithoutABuiltInCameraWaits() {
        #expect(CameraChooser.choose(from: [iphone], source: .mac, pinned: nil, allowBuiltIn: false) == nil)
    }

    @Test func iphoneModeIsTheDefaultBehavior() {
        #expect(
            CameraChooser.choose(from: [builtIn, iphone], source: .iphone, pinned: nil, allowBuiltIn: false) == iphone)
    }
}
