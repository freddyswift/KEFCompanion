import Darwin
import Foundation

func sendWakeOnLAN(macAddress: String) -> Bool {
    let hex = macAddress
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "-", with: "")
    guard hex.count == 12 else { return false }

    var macBytes = [UInt8]()
    var index = hex.startIndex
    for _ in 0..<6 {
        let next = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<next], radix: 16) else { return false }
        macBytes.append(byte)
        index = next
    }

    var packet = [UInt8](repeating: 0xFF, count: 6)
    for _ in 0..<16 {
        packet.append(contentsOf: macBytes)
    }

    let socketFileDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
    guard socketFileDescriptor >= 0 else { return false }
    defer { close(socketFileDescriptor) }

    var broadcast: Int32 = 1
    setsockopt(
        socketFileDescriptor,
        SOL_SOCKET,
        SO_BROADCAST,
        &broadcast,
        socklen_t(MemoryLayout<Int32>.size)
    )

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(9).bigEndian
    address.sin_addr.s_addr = INADDR_BROADCAST

    let sentByteCount = packet.withUnsafeBytes { buffer in
        withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                sendto(
                    socketFileDescriptor,
                    buffer.baseAddress,
                    buffer.count,
                    0,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
    }

    return sentByteCount == packet.count
}
