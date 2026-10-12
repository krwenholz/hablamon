import JSONSchemaBuilder

/// One line of `sessions/<session>.jsonl`. The `type` field selects the case.
///
/// The transcript is append-only history: its schema only gains optional fields.
public enum TranscriptEntry: Sendable, Equatable {
    case line(TranscriptLine)
    case gap(TranscriptGap)
    case recalibrated(TranscriptRecalibration)
}

extension TranscriptEntry: VersionedDocument {
    public static let currentVersion = 1
    public static let schemaName = "transcript-entry"
    public static let versionKey = "v"

    public static var schema: some JSONSchemaComponent<TranscriptEntry> {
        JSONComposition.OneOf(into: TranscriptEntry.self) {
            TranscriptLine.schema.map { TranscriptEntry.line($0) }
            TranscriptGap.schema.map { TranscriptEntry.gap($0) }
            TranscriptRecalibration.schema.map { TranscriptEntry.recalibrated($0) }
        }
    }

    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: any Decoder) throws {
        let kind = try decoder.container(keyedBy: TypeKey.self).decode(String.self, forKey: .type)
        switch kind {
        case "line": self = .line(try TranscriptLine(from: decoder))
        case "gap": self = .gap(try TranscriptGap(from: decoder))
        case "recalibrated": self = .recalibrated(try TranscriptRecalibration(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: try decoder.container(keyedBy: TypeKey.self),
                debugDescription: "unknown transcript entry type \"\(kind)\""
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .line(let line): try line.encode(to: encoder)
        case .gap(let gap): try gap.encode(to: encoder)
        case .recalibrated(let recalibration): try recalibration.encode(to: encoder)
        }
    }
}

/// A spoken dialogue page.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct TranscriptLine: Codable, Sendable, Equatable {
    @NumberOptions(.minimum(1))
    public var v: Int
    public var type: Kind
    /// ISO 8601 timestamp with offset.
    @StringOptions(.format("date-time"))
    public var ts: String
    public var session: String
    /// Position in the session, starting at 1.
    @NumberOptions(.minimum(1))
    public var seq: Int
    /// Resolved character name, or `narrator`.
    public var speaker: String
    /// Name-tag text as OCR read it.
    public var speakerRaw: String?
    public var text: String
    public var ocrConfidence: OCRConfidence
    /// Box crop relative to the session folder.
    public var crop: String?
    public var engine: SpeechEngineID
    /// Human-readable voice settings used, such as `es-ES male p0.9 r0.95`.
    public var voice: String
    public var translation: String?
    public var translationSource: String?

    @Schemable
    public enum Kind: String, Codable, Sendable {
        case line
    }

    public init(
        v: Int = TranscriptEntry.currentVersion,
        type: Kind = .line,
        ts: String,
        session: String,
        seq: Int,
        speaker: String,
        speakerRaw: String? = nil,
        text: String,
        ocrConfidence: OCRConfidence,
        crop: String? = nil,
        engine: SpeechEngineID,
        voice: String,
        translation: String? = nil,
        translationSource: String? = nil
    ) {
        self.v = v
        self.type = type
        self.ts = ts
        self.session = session
        self.seq = seq
        self.speaker = speaker
        self.speakerRaw = speakerRaw
        self.text = text
        self.ocrConfidence = ocrConfidence
        self.crop = crop
        self.engine = engine
        self.voice = voice
        self.translation = translation
        self.translationSource = translationSource
    }
}

@Schemable
@ObjectOptions(.additionalProperties(false))
public struct OCRConfidence: Codable, Sendable, Equatable {
    @NumberOptions(.minimum(0), .maximum(1))
    public var mean: Double
    @NumberOptions(.minimum(0), .maximum(1))
    public var min: Double

    public init(mean: Double, min: Double) {
        self.mean = mean
        self.min = min
    }
}

/// Time the camera wasn't watching; lines shown then are not recovered.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct TranscriptGap: Codable, Sendable, Equatable {
    @NumberOptions(.minimum(1))
    public var v: Int
    public var type: Kind
    @StringOptions(.format("date-time"))
    public var ts: String
    public var session: String
    public var reason: Reason
    @NumberOptions(.minimum(0))
    public var durationSec: Double

    @Schemable
    public enum Kind: String, Codable, Sendable {
        case gap
    }

    @Schemable
    public enum Reason: String, Codable, Sendable, CaseIterable {
        /// The phone was picked up (Continuity Camera suspended).
        case cameraPaused = "camera_paused"
        /// The pinned camera disconnected.
        case cameraLost = "camera_lost"
        /// The camera was running but the TV screen couldn't be found.
        case screenLost = "screen_lost"
    }

    public init(
        v: Int = TranscriptEntry.currentVersion,
        type: Kind = .gap,
        ts: String,
        session: String,
        reason: Reason,
        durationSec: Double
    ) {
        self.v = v
        self.type = type
        self.ts = ts
        self.session = session
        self.reason = reason
        self.durationSec = durationSec
    }
}

/// The screen quad changed mid-session.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct TranscriptRecalibration: Codable, Sendable, Equatable {
    @NumberOptions(.minimum(1))
    public var v: Int
    public var type: Kind
    @StringOptions(.format("date-time"))
    public var ts: String
    public var session: String
    public var trigger: Trigger

    @Schemable
    public enum Kind: String, Codable, Sendable {
        case recalibrated
    }

    @Schemable
    public enum Trigger: String, Codable, Sendable, CaseIterable {
        /// Re-found automatically after the phone moved.
        case automatic
        /// The player confirmed or dragged the corners.
        case manual
    }

    public init(
        v: Int = TranscriptEntry.currentVersion,
        type: Kind = .recalibrated,
        ts: String,
        session: String,
        trigger: Trigger
    ) {
        self.v = v
        self.type = type
        self.ts = ts
        self.session = session
        self.trigger = trigger
    }
}
