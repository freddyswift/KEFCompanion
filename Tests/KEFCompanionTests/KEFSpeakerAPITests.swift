import Foundation
import XCTest
@testable import KEFCompanion

final class KEFSpeakerAPITests: XCTestCase {
    func testGetStatusBuildsGetDataRequest() async throws {
        let (api, recorder) = makeAPI { _ in
            .json(#"[{"kefSpeakerStatus":"powerOn"}]"#)
        }

        let status = try await api.getStatus()

        XCTAssertEqual(status, .powerOn)
        let requests = recorder.requests
        XCTAssertEqual(requests.count, 1)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.path, "/api/getData")
        XCTAssertEqual(request.queryValue("path"), "settings:/kef/host/speakerStatus")
        XCTAssertEqual(request.queryValue("roles"), "value")
    }

    func testSetVolumeUsesGetSetDataForLegacyModel() async throws {
        let (api, recorder) = makeAPI { request in
            switch request.url.path {
            case "/api/getData" where request.queryValue("path") == "settings:/releasetext":
                return .json(#"[{"string_":"LS50W_4.0"}]"#)
            case "/api/setData":
                return .empty()
            default:
                throw URLError(.badURL)
            }
        }

        try await api.setVolume(130)

        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)

        let modelRequest = try XCTUnwrap(requests.first)
        XCTAssertEqual(modelRequest.method, "GET")
        XCTAssertEqual(modelRequest.url.path, "/api/getData")
        XCTAssertEqual(modelRequest.queryValue("path"), "settings:/releasetext")

        let setRequest = try XCTUnwrap(requests.last)
        XCTAssertEqual(setRequest.method, "GET")
        XCTAssertEqual(setRequest.url.path, "/api/setData")
        XCTAssertEqual(setRequest.queryValue("path"), "player:volume")
        XCTAssertEqual(setRequest.queryValue("roles"), "value")
        XCTAssertNil(setRequest.body)

        let value = try decodedSetValue(fromQueryOf: setRequest)
        XCTAssertEqual(value["type"], .string("i32_"))
        XCTAssertEqual(value["i32_"], .int(100))
    }

    func testSetSourceUsesPostSetDataForModelAlias() async throws {
        let (api, recorder) = makeAPI { request in
            switch request.url.path {
            case "/api/getData" where request.queryValue("path") == "settings:/releasetext":
                return .json(#"[{"string_":"LS50W2_4.0"}]"#)
            case "/api/setData":
                return .json(#"{}"#)
            default:
                throw URLError(.badURL)
            }
        }

        try await api.setSource(.tv)

        let requests = recorder.requests
        XCTAssertEqual(requests.count, 2)

        let modelRequest = try XCTUnwrap(requests.first)
        XCTAssertEqual(modelRequest.method, "GET")
        XCTAssertEqual(modelRequest.queryValue("path"), "settings:/releasetext")

        let postRequest = try XCTUnwrap(requests.last)
        XCTAssertEqual(postRequest.method, "POST")
        XCTAssertEqual(postRequest.url.path, "/api/setData")
        XCTAssertEqual(postRequest.headers["Content-Type"], "application/json")
        XCTAssertNil(postRequest.url.query)

        let body = try decodedSetDataRequest(fromBodyOf: postRequest)
        XCTAssertEqual(body.path, "settings:/kef/play/physicalSource")
        XCTAssertEqual(body.roles, "value")
        XCTAssertEqual(body.value["type"], .string("kefPhysicalSource"))
        XCTAssertEqual(body.value["kefPhysicalSource"], .string("tv"))
    }

    func testGetDataThrowsAPIErrorForHTTPFailure() async throws {
        let (api, recorder) = makeAPI { _ in
            .empty(statusCode: 503)
        }

        do {
            _ = try await api.getStatus()
            XCTFail("Expected HTTP failure to throw")
        } catch KEFError.apiError(let message) {
            XCTAssertEqual(message, "Speaker returned HTTP 503")
        } catch {
            XCTFail("Expected KEFError.apiError, got \(error)")
        }

        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testGetDataThrowsInvalidResponseForMalformedPayload() async throws {
        let (api, _) = makeAPI { _ in
            .json(#"{"kefSpeakerStatus":"powerOn"}"#)
        }

        do {
            _ = try await api.getStatus()
            XCTFail("Expected malformed payload to throw")
        } catch KEFError.invalidResponse {
            // Expected.
        } catch {
            XCTFail("Expected KEFError.invalidResponse, got \(error)")
        }
    }

    func testSetDataThrowsInvalidResponseForMalformedPayload() async throws {
        let (api, _) = makeAPI { request in
            switch request.url.path {
            case "/api/getData" where request.queryValue("path") == "settings:/releasetext":
                return .json(#"[{"string_":"LS50W_4.0"}]"#)
            case "/api/setData":
                return .json("not-json")
            default:
                throw URLError(.badURL)
            }
        }

        do {
            try await api.setVolume(25)
            XCTFail("Expected malformed setData payload to throw")
        } catch KEFError.invalidResponse {
            // Expected.
        } catch {
            XCTFail("Expected KEFError.invalidResponse, got \(error)")
        }
    }

    func testSnapshotFallsBackToIndividualRequestsWhenBatchedPayloadIsInvalid() async throws {
        let expectedBatchedPath = [
            "settings:/kef/host/speakerStatus",
            "settings:/kef/play/physicalSource",
            "player:volume",
            "settings:/deviceName",
            "settings:/releasetext",
        ].joined(separator: ",")

        let (api, recorder) = makeAPI { request in
            guard request.url.path == "/api/getData" else {
                throw URLError(.badURL)
            }

            switch request.queryValue("path") {
            case expectedBatchedPath:
                return .json("[]")
            case "settings:/kef/host/speakerStatus":
                return .json(#"[{"kefSpeakerStatus":"powerOn"}]"#)
            case "settings:/kef/play/physicalSource":
                return .json(#"[{"kefPhysicalSource":"tv"}]"#)
            case "player:volume":
                return .json(#"[{"i32_":24}]"#)
            case "settings:/deviceName":
                return .json(#"[{"string_":"Living Room"}]"#)
            case "settings:/releasetext":
                return .json(#"[{"string_":"LSX2_4.0"}]"#)
            default:
                throw URLError(.badURL)
            }
        }

        let snapshot = try await api.getSnapshot()

        XCTAssertEqual(
            snapshot,
            SpeakerSnapshot(
                status: .powerOn,
                source: .tv,
                volume: 24,
                name: "Living Room",
                model: "LSX2"
            )
        )

        let requests = recorder.requests
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(requests.first?.queryValue("path"), expectedBatchedPath)
        XCTAssertEqual(
            Set(requests.dropFirst().compactMap { $0.queryValue("path") }),
            Set(expectedBatchedPath.components(separatedBy: ","))
        )
    }

    func testDecodesDynamicDataEntries() throws {
        let json = """
        [
          {
            "state": "playing",
            "i32_": 42,
            "trackRoles": {
              "title": "Song",
              "mediaData": {
                "metaData": {
                  "artist": "Artist",
                  "album": "Album"
                }
              }
            }
          }
        ]
        """

        let entries = try KEFSpeakerAPI.decodeDataEntries(Data(json.utf8))
        XCTAssertEqual(entries.first?.string("state"), "playing")
        XCTAssertEqual(entries.first?.int("i32_"), 42)
        XCTAssertEqual(entries.first?.object("trackRoles")?["title"]?.stringValue, "Song")
    }

    func testRejectsNonArrayResponse() {
        XCTAssertThrowsError(try KEFSpeakerAPI.decodeDataEntries(Data(#"{"state":"playing"}"#.utf8)))
    }

    private func makeAPI(
        host: String = UUID().uuidString.lowercased() + ".test",
        responder: @escaping (RecordedHTTPRequest) throws -> StubbedHTTPResponse
    ) -> (KEFSpeakerAPI, RequestRecorder) {
        let recorder = RequestRecorder()
        URLProtocolStub.register(host: host) { request in
            recorder.append(request)
            return try responder(request)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let session = URLSession(configuration: configuration)

        addTeardownBlock {
            session.invalidateAndCancel()
            URLProtocolStub.unregister(host: host)
        }

        return (KEFSpeakerAPI(host: host, session: session), recorder)
    }

    private func decodedSetValue(fromQueryOf request: RecordedHTTPRequest) throws -> [String: KEFJSONValue] {
        let value = try XCTUnwrap(request.queryValue("value"))
        let data = try XCTUnwrap(value.data(using: .utf8))
        return try JSONDecoder().decode([String: KEFJSONValue].self, from: data)
    }

    private func decodedSetDataRequest(fromBodyOf request: RecordedHTTPRequest) throws -> DecodedSetDataRequest {
        let body = try XCTUnwrap(request.body)
        return try JSONDecoder().decode(DecodedSetDataRequest.self, from: body)
    }
}

private struct DecodedSetDataRequest: Decodable {
    var path: String
    var roles: String
    var value: [String: KEFJSONValue]
}

private struct StubbedHTTPResponse {
    var statusCode: Int
    var body: Data
    var headers: [String: String]

    static func empty(statusCode: Int = 200, headers: [String: String] = [:]) -> StubbedHTTPResponse {
        StubbedHTTPResponse(statusCode: statusCode, body: Data(), headers: headers)
    }

    static func json(_ json: String, statusCode: Int = 200) -> StubbedHTTPResponse {
        StubbedHTTPResponse(
            statusCode: statusCode,
            body: Data(json.utf8),
            headers: ["Content-Type": "application/json"]
        )
    }
}

private struct RecordedHTTPRequest {
    var method: String
    var url: URL
    var headers: [String: String]
    var body: Data?

    init(request: URLRequest) {
        method = request.httpMethod ?? "GET"
        url = request.url!
        headers = request.allHTTPHeaderFields ?? [:]
        body = Self.bodyData(from: request)
    }

    func queryValue(_ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            return nil
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count > 0 {
                data.append(buffer, count: count)
            } else {
                break
            }
        }

        return data
    }
}

private final class RequestRecorder {
    private let lock = NSLock()
    private var storedRequests: [RecordedHTTPRequest] = []

    var requests: [RecordedHTTPRequest] {
        lock.withLock { storedRequests }
    }

    func append(_ request: RecordedHTTPRequest) {
        lock.withLock {
            storedRequests.append(request)
        }
    }
}

private final class URLProtocolStub: URLProtocol {
    typealias Handler = (RecordedHTTPRequest) throws -> StubbedHTTPResponse

    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]

    static func register(host: String, handler: @escaping Handler) {
        lock.withLock {
            handlers[host] = handler
        }
    }

    static func unregister(host: String) {
        _ = lock.withLock {
            handlers.removeValue(forKey: host)
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else {
            return false
        }

        return lock.withLock {
            handlers[host] != nil
        }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let request = RecordedHTTPRequest(request: request)
        guard let handler = Self.handler(for: request.url.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let stubbedResponse = try handler(request)
            let response = HTTPURLResponse(
                url: request.url,
                statusCode: stubbedResponse.statusCode,
                httpVersion: nil,
                headerFields: stubbedResponse.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stubbedResponse.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func handler(for host: String?) -> Handler? {
        guard let host else {
            return nil
        }

        return lock.withLock {
            handlers[host]
        }
    }
}
