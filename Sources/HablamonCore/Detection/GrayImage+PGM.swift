/// Binary PGM (P5), the simplest grayscale file format, for the calibration reference thumbnail.
extension GrayImage {
    public enum PGMError: Error {
        case malformed
    }

    public var pgm: [UInt8] {
        Array("P5\n\(width) \(height)\n255\n".utf8) + pixels
    }

    public init(pgm bytes: [UInt8]) throws {
        // Header: magic, width, height, max value, each separated by whitespace, then one whitespace byte.
        var fields: [String] = []
        var index = 0
        var current = ""
        while fields.count < 4, index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
                if !current.isEmpty {
                    fields.append(current)
                    current = ""
                }
            } else {
                current.append(Character(UnicodeScalar(byte)))
            }
        }
        guard fields.count == 4, fields[0] == "P5", let width = Int(fields[1]), let height = Int(fields[2]),
            fields[3] == "255", width > 0, height > 0, bytes.count - index == width * height
        else { throw PGMError.malformed }
        self.init(width: width, height: height, pixels: Array(bytes[index...]))
    }
}
