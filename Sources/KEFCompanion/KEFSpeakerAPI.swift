import Foundation

/// Protocol used by `AppState` and settings code instead of depending directly
/// on a concrete network client. Tests can use lightweight fakes when exercising
/// connection and action flow.
protocol KEFSpeakerClient: AnyObject, Sendable {
    var host: String { get }

    func getStatus() async throws -> SpeakerStatus
    func getSource() async throws -> SpeakerSource
    func getVolume() async throws -> Int
    func getSpeakerName() async throws -> String
    func getModel() async throws -> String
    func getIsPlaying() async throws -> Bool
    func getNowPlayingInfo() async throws -> NowPlayingInfo
    func setVolume(_ volume: Int) async throws
    func setSource(_ source: SpeakerSource) async throws
    func powerOn() async throws
    func shutdown() async throws
    func togglePlayPause() async throws
    func nextTrack() async throws
    func previousTrack() async throws
    func testConnection() async -> Bool
}

final class KEFSpeakerAPI: Sendable {
    private static let postSetDataModels: Set<String> = ["LS50WII", "LSXII", "LSXIILT"]
    private static let modelAliases: [String: String] = [
        "LS50W2": "LS50WII",
        "LSX2": "LSXII",
        "LSX2LT": "LSXIILT",
    ]

    let host: String
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(host: String) {
        self.host = host
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        self.session = URLSession(configuration: config)
    }

    // MARK: - Low-level API

    private func getData(path: String, roles: String = "value") async throws -> [KEFDataEntry] {
        guard var components = URLComponents(string: "http://\(host)/api/getData") else {
            throw KEFError.connectionFailed
        }
        components.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "roles", value: roles),
        ]
        guard let url = components.url else { throw KEFError.connectionFailed }
        let data = try await data(from: url)
        return try Self.decodeDataEntries(data, decoder: decoder)
    }

    private func firstData(path: String, roles: String = "value") async throws -> KEFDataEntry {
        guard let first = try await getData(path: path, roles: roles).first else {
            throw KEFError.invalidResponse
        }
        return first
    }

    private func setData(path: String, roles: String = "value", value: KEFSetValue) async throws {
        if try await usesPostForSetData() {
            try await postSetData(path: path, roles: roles, value: value)
        } else {
            try await getSetData(path: path, roles: roles, value: value)
        }
    }

    private func getSetData(path: String, roles: String, value: KEFSetValue) async throws {
        guard var components = URLComponents(string: "http://\(host)/api/setData") else {
            throw KEFError.connectionFailed
        }
        let valueData = try encoder.encode(value)
        guard let valueString = String(data: valueData, encoding: .utf8) else {
            throw KEFError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "roles", value: roles),
            URLQueryItem(name: "value", value: valueString),
        ]
        guard let url = components.url else { throw KEFError.connectionFailed }
        let data = try await data(from: url)
        try validateSetDataResponse(data)
    }

    private func postSetData(path: String, roles: String, value: KEFSetValue) async throws {
        guard let url = URL(string: "http://\(host)/api/setData") else {
            throw KEFError.connectionFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(KEFSetDataRequest(path: path, roles: roles, value: value))

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response)
        try validateSetDataResponse(data)
    }

    private func data(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response)
        return data
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw KEFError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw KEFError.apiError("Speaker returned HTTP \(httpResponse.statusCode)")
        }
    }

    private func validateSetDataResponse(_ data: Data) throws {
        guard !data.isEmpty else { return }
        let response = try decoder.decode(KEFSetDataResponse.self, from: data)
        if let error = response.error {
            let message = error.message ?? "Speaker rejected command"
            throw KEFError.apiError(message)
        }
    }

    private func usesPostForSetData() async throws -> Bool {
        let model = try await getModel()
        let normalizedModel = Self.modelAliases[model] ?? model
        return Self.postSetDataModels.contains(normalizedModel)
    }

    // MARK: - Read

    func getStatus() async throws -> SpeakerStatus {
        let data = try await firstData(path: "settings:/kef/host/speakerStatus")
        let raw = data.string("kefSpeakerStatus") ?? "standby"
        return SpeakerStatus(rawValue: raw) ?? .standby
    }

    func getSource() async throws -> SpeakerSource {
        let data = try await firstData(path: "settings:/kef/play/physicalSource")
        let raw = data.string("kefPhysicalSource") ?? "standby"
        return SpeakerSource(rawValue: raw) ?? .wifi
    }

    func getVolume() async throws -> Int {
        let data = try await firstData(path: "player:volume")
        return data.int("i32_") ?? 0
    }

    func getSpeakerName() async throws -> String {
        let data = try await firstData(path: "settings:/deviceName")
        return data.string("string_") ?? "KEF Speaker"
    }

    func getModel() async throws -> String {
        let data = try await firstData(path: "settings:/releasetext")
        let raw = data.string("string_") ?? ""
        return raw.components(separatedBy: "_").first ?? raw
    }

    private func getPlayerData() async throws -> KEFDataEntry {
        try await firstData(path: "player:player/data")
    }

    func getIsPlaying() async throws -> Bool {
        let data = try await getPlayerData()
        return data.string("state") == "playing"
    }

    func getNowPlayingInfo() async throws -> NowPlayingInfo {
        let data = try await getPlayerData()
        let trackRoles = data.object("trackRoles")
        let mediaData = trackRoles?["mediaData"]?.objectValue
        let metadata = mediaData?["metaData"]?.objectValue

        return NowPlayingInfo(
            title: trackRoles?["title"]?.stringValue,
            artist: metadata?["artist"]?.stringValue,
            album: metadata?["album"]?.stringValue
        )
    }

    // MARK: - Write

    func setVolume(_ volume: Int) async throws {
        let clamped = max(0, min(100, volume))
        try await setData(
            path: "player:volume",
            value: ["type": .string("i32_"), "i32_": .int(clamped)]
        )
    }

    func setSource(_ source: SpeakerSource) async throws {
        try await setData(
            path: "settings:/kef/play/physicalSource",
            value: ["type": .string("kefPhysicalSource"), "kefPhysicalSource": .string(source.rawValue)]
        )
    }

    func powerOn() async throws {
        try await setData(
            path: "settings:/kef/play/physicalSource",
            value: ["type": .string("kefPhysicalSource"), "kefPhysicalSource": .string("powerOn")]
        )
    }

    func shutdown() async throws {
        try await setData(
            path: "settings:/kef/play/physicalSource",
            value: ["type": .string("kefPhysicalSource"), "kefPhysicalSource": .string("standby")]
        )
    }

    func togglePlayPause() async throws {
        try await setData(
            path: "player:player/control",
            roles: "activate",
            value: ["control": .string("pause")]
        )
    }

    func nextTrack() async throws {
        try await setData(
            path: "player:player/control",
            roles: "activate",
            value: ["control": .string("next")]
        )
    }

    func previousTrack() async throws {
        try await setData(
            path: "player:player/control",
            roles: "activate",
            value: ["control": .string("previous")]
        )
    }

    func testConnection() async -> Bool {
        do {
            _ = try await getStatus()
            return true
        } catch {
            return false
        }
    }

    static func decodeDataEntries(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> [KEFDataEntry] {
        do {
            return try decoder.decode([KEFDataEntry].self, from: data)
        } catch {
            throw KEFError.invalidResponse
        }
    }
}

extension KEFSpeakerAPI: KEFSpeakerClient {}

typealias KEFSetValue = [String: KEFJSONValue]

/// Flexible JSON value used at the KEF API boundary.
///
/// The speaker returns endpoint-specific keys such as `kefSpeakerStatus`,
/// `i32_`, or nested `trackRoles`. Decoding into this enum preserves the dynamic
/// shape at the edge while preventing untyped `[String: Any]` from spreading
/// through the rest of the codebase.
enum KEFJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: KEFJSONValue])
    case array([KEFJSONValue])
    case null

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .double(let value) where value.rounded() == value:
            return Int(value)
        default:
            return nil
        }
    }

    var objectValue: [String: KEFJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    init(from decoder: Decoder) throws {
        if let keyedContainer = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: KEFJSONValue] = [:]
            for key in keyedContainer.allKeys {
                object[key.stringValue] = try keyedContainer.decode(KEFJSONValue.self, forKey: key)
            }
            self = .object(object)
            return
        }

        if var unkeyedContainer = try? decoder.unkeyedContainer() {
            var array: [KEFJSONValue] = []
            while !unkeyedContainer.isAtEnd {
                array.append(try unkeyedContainer.decode(KEFJSONValue.self))
            }
            self = .array(array)
            return
        }

        let singleValueContainer = try decoder.singleValueContainer()
        if singleValueContainer.decodeNil() {
            self = .null
        } else if let value = try? singleValueContainer.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? singleValueContainer.decode(Int.self) {
            self = .int(value)
        } else if let value = try? singleValueContainer.decode(Double.self) {
            self = .double(value)
        } else if let value = try? singleValueContainer.decode(String.self) {
            self = .string(value)
        } else {
            throw KEFError.invalidResponse
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .int(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .double(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .object(let value):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, nestedValue) in value {
                try container.encode(nestedValue, forKey: DynamicCodingKey(stringValue: key))
            }
        case .array(let value):
            var container = encoder.unkeyedContainer()
            for nestedValue in value {
                try container.encode(nestedValue)
            }
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }
}

struct KEFDataEntry: Decodable, Equatable, Sendable {
    let values: [String: KEFJSONValue]

    init(values: [String: KEFJSONValue]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var values: [String: KEFJSONValue] = [:]
        for key in container.allKeys {
            values[key.stringValue] = try container.decode(KEFJSONValue.self, forKey: key)
        }
        self.values = values
    }

    func string(_ key: String) -> String? {
        values[key]?.stringValue
    }

    func int(_ key: String) -> Int? {
        values[key]?.intValue
    }

    func object(_ key: String) -> [String: KEFJSONValue]? {
        values[key]?.objectValue
    }
}

private struct KEFSetDataRequest: Encodable {
    var path: String
    var roles: String
    var value: KEFSetValue
}

private struct KEFSetDataResponse: Decodable {
    struct ErrorPayload: Decodable {
        var message: String?
    }

    var error: ErrorPayload?
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
