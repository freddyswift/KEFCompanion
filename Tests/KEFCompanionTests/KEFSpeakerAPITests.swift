import XCTest
@testable import KEFCompanion

final class KEFSpeakerAPITests: XCTestCase {
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
}
