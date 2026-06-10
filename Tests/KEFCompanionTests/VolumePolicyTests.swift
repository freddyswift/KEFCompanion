import XCTest
@testable import KEFCompanion

final class VolumePolicyTests: XCTestCase {
    func testClampsStepSize() {
        XCTAssertEqual(VolumePolicy.clampedStepSize(-5), 1)
        XCTAssertEqual(VolumePolicy.clampedStepSize(5), 5)
        XCTAssertEqual(VolumePolicy.clampedStepSize(50), 25)
    }

    func testNormalizesAnyValueMode() {
        let policy = VolumePolicy(usesFixedSteps: false, stepSize: 5)
        XCTAssertEqual(policy.normalizedVolume(-1), 0)
        XCTAssertEqual(policy.normalizedVolume(37), 37)
        XCTAssertEqual(policy.normalizedVolume(101), 100)
    }

    func testNormalizesFixedStepMode() {
        let policy = VolumePolicy(usesFixedSteps: true, stepSize: 5)
        XCTAssertEqual(policy.normalizedVolume(37), 35)
        XCTAssertEqual(policy.normalizedVolume(38), 40)
        XCTAssertEqual(policy.normalizedVolume(99), 100)
    }

    func testNextVolumeUsesConfiguredSteps() {
        let policy = VolumePolicy(usesFixedSteps: true, stepSize: 5)
        XCTAssertEqual(policy.nextVolume(from: 37, direction: 1), 40)
        XCTAssertEqual(policy.nextVolume(from: 40, direction: -1), 35)
        XCTAssertEqual(policy.nextVolume(from: 0, direction: -1), 0)
        XCTAssertEqual(policy.nextVolume(from: 100, direction: 1), 100)
    }
}
