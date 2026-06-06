import Foundation

struct DiscoveredSpeaker: Identifiable, Equatable, Hashable {
    let id: String
    let name: String
    let host: String
    let macAddress: String?
}

struct NowPlayingInfo: Equatable {
    var title: String?
    var artist: String?
    var album: String?

    var hasInfo: Bool {
        title != nil || artist != nil
    }
}

enum VolumeKeyRoutingMode: String, CaseIterable, Identifiable {
    case mac
    case auto
    case speaker

    var id: String { rawValue }

    var requiresMediaKeyAccess: Bool {
        switch self {
        case .mac:
            false
        case .auto, .speaker:
            true
        }
    }
}

enum SpeakerSource: String, CaseIterable, Identifiable {
    case wifi
    case bluetooth
    case tv
    case optical
    case coaxial
    case analog
    case usb

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wifi:
            "WiFi"
        case .bluetooth:
            "Bluetooth"
        case .tv:
            "TV"
        case .optical:
            "Optical"
        case .coaxial:
            "Coaxial"
        case .analog:
            "Analog"
        case .usb:
            "USB"
        }
    }

    static let inputSources: [SpeakerSource] = [
        .wifi,
        .bluetooth,
        .tv,
        .optical,
        .coaxial,
        .analog,
        .usb,
    ]
}

enum SpeakerStatus: String {
    case powerOn
    case standby
}

enum KEFError: LocalizedError {
    case invalidResponse
    case connectionFailed
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from speaker"
        case .connectionFailed:
            "Could not connect to speaker"
        case .apiError(let message):
            message
        }
    }
}
