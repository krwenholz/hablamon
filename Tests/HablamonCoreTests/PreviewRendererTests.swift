#if canImport(CoreImage)
    import CoreImage
    import Foundation
    import Testing

    @testable import HablamonCore

    @Suite struct PreviewRendererTests {
        final class Count: @unchecked Sendable {
            private let lock = NSLock()
            private var widths: [Int] = []
            func add(_ width: Int) { lock.withLock { widths.append(width) } }
            var all: [Int] { lock.withLock { widths } }
        }

        let frame = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        @Test func rendersAboutTenPerSecondWhileEnabled() {
            let count = Count()
            let renderer = PreviewRenderer { image, scale in
                count.add(image.width)
                #expect(abs(scale - 640.0 / 1920) < 0.0001)
            }
            renderer.isEnabled = true
            for index in 0..<60 {  // two seconds at 30 fps
                renderer.offer(frame, at: start.addingTimeInterval(Double(index) / 30), wait: true)
            }
            #expect((19...21).contains(count.all.count))
            #expect(count.all.allSatisfy { $0 == 640 })
        }

        @Test func silentWhileDisabled() {
            let count = Count()
            let renderer = PreviewRenderer { image, _ in count.add(image.width) }
            for index in 0..<30 { renderer.offer(frame, at: start.addingTimeInterval(Double(index) / 30), wait: true) }
            #expect(count.all.isEmpty)
        }
    }
#endif
