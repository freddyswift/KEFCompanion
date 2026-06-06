import Darwin
import Foundation
import Network

@MainActor
final class KEFDiscovery: ObservableObject {
    @Published var speakers: [DiscoveredSpeaker] = []
    @Published var isSearching = false

    private var httpBrowser: NWBrowser?
    private var raopBrowser: NWBrowser?
    private var stopTask: Task<Void, Never>?
    private var discoveredMACs: [String: String] = [:]

    func startDiscovery() {
        stopDiscovery()
        speakers = []
        discoveredMACs = [:]
        isSearching = true

        let params = NWParameters()
        params.includePeerToPeer = true

        raopBrowser = NWBrowser(for: .bonjour(type: "_raop._tcp", domain: nil), using: params)
        raopBrowser?.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                guard case .service(let name, _, _, _) = result.endpoint,
                      let parsedService = Self.parseRAOPServiceName(name) else { continue }

                Task { @MainActor in
                    self?.recordMAC(parsedService.macAddress, for: parsedService.speakerName)
                }
            }
        }
        raopBrowser?.start(queue: .global())

        httpBrowser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: nil), using: params)
        httpBrowser?.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                guard case .service(let name, let type, let domain, _) = result.endpoint,
                      Self.isLikelyKEFSpeakerService(name) else { continue }

                self?.resolveService(name: name, type: type, domain: domain)
            }
        }
        httpBrowser?.start(queue: .global())

        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.stopDiscovery()
        }
    }

    func stopDiscovery() {
        stopTask?.cancel()
        stopTask = nil
        httpBrowser?.cancel()
        httpBrowser = nil
        raopBrowser?.cancel()
        raopBrowser = nil
        isSearching = false
    }

    private func recordMAC(_ macAddress: String, for speakerName: String) {
        discoveredMACs[speakerName] = macAddress

        guard let index = speakers.firstIndex(where: { $0.name == speakerName && $0.macAddress == nil }) else {
            return
        }

        let speaker = speakers[index]
        speakers[index] = DiscoveredSpeaker(
            id: speaker.id,
            name: speaker.name,
            host: speaker.host,
            macAddress: macAddress
        )
    }

    private func addSpeaker(name: String, host: String) {
        let macAddress = discoveredMACs[name]

        if let index = speakers.firstIndex(where: { $0.host == host }) {
            guard speakers[index].macAddress == nil, let macAddress else { return }

            let speaker = speakers[index]
            speakers[index] = DiscoveredSpeaker(
                id: speaker.id,
                name: speaker.name,
                host: speaker.host,
                macAddress: macAddress
            )
            return
        }

        speakers.append(
            DiscoveredSpeaker(id: name, name: name, host: host, macAddress: macAddress)
        )
    }

    /// Resolve a Bonjour service to an IPv4 address using dns_sd APIs.
    ///
    /// NWConnection's IP resolution can return IPv6-only on some networks,
    /// so we use DNSServiceResolve to get the actual .local hostname, then
    /// getaddrinfo to look up the IPv4 address.
    nonisolated private func resolveService(name: String, type: String, domain: String) {
        DispatchQueue.global().async { [weak self] in
            guard let hostname = Self.resolveServiceHostname(name: name, type: type, domain: domain) else {
                return
            }
            guard let ipv4 = Self.resolveToIPv4(hostname) else {
                return
            }

            Task { @MainActor in
                guard let self else { return }
                self.addSpeaker(name: name, host: ipv4)
            }
        }
    }

    nonisolated private static func isLikelyKEFSpeakerService(_ name: String) -> Bool {
        let uppercasedName = name.uppercased()
        return uppercasedName.contains("LSX") ||
            uppercasedName.contains("LS50") ||
            uppercasedName.contains("LS60") ||
            uppercasedName.contains("KEF")
    }

    nonisolated private static func parseRAOPServiceName(_ name: String) -> (speakerName: String, macAddress: String)? {
        guard isLikelyKEFSpeakerService(name),
              let separatorIndex = name.firstIndex(of: "@") else {
            return nil
        }

        let rawMAC = String(name[..<separatorIndex])
        guard rawMAC.count == 12, rawMAC.allSatisfy(\.isHexDigit) else {
            return nil
        }

        let macAddress = stride(from: 0, to: 12, by: 2)
            .map { offset -> String in
                let start = rawMAC.index(rawMAC.startIndex, offsetBy: offset)
                let end = rawMAC.index(start, offsetBy: 2)
                return String(rawMAC[start..<end])
            }
            .joined(separator: ":")
        let speakerName = String(name[name.index(after: separatorIndex)...])

        return (speakerName, macAddress)
    }

    /// Use DNSServiceResolve to get the .local hostname for a Bonjour service.
    nonisolated private static func resolveServiceHostname(name: String, type: String, domain: String) -> String? {
        class Box { var value: String? }
        let box = Box()
        var sdRef: DNSServiceRef?

        let callback: DNSServiceResolveReply = {
            _, _, _, errorCode, _, hosttarget, _, _, _, context in
            guard errorCode == kDNSServiceErr_NoError,
                  let hosttarget,
                  let context else { return }
            let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
            box.value = String(cString: hosttarget)
        }

        let err = DNSServiceResolve(
            &sdRef, 0, 0,
            name, type, domain,
            callback,
            Unmanaged.passUnretained(box).toOpaque()
        )
        guard err == kDNSServiceErr_NoError, let sdRef else { return nil }
        defer { DNSServiceRefDeallocate(sdRef) }

        // Wait for the resolve callback (up to 5 seconds)
        let fd = DNSServiceRefSockFD(sdRef)
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        if poll(&pfd, 1, 5000) > 0 {
            DNSServiceProcessResult(sdRef)
        }

        return box.value
    }

    /// Use getaddrinfo to resolve a hostname to an IPv4 address.
    nonisolated private static func resolveToIPv4(_ hostname: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, nil, &hints, &result) == 0, let addr = result else {
            return nil
        }
        defer { freeaddrinfo(result) }

        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(
            addr.pointee.ai_addr, socklen_t(addr.pointee.ai_addrlen),
            &buf, socklen_t(buf.count),
            nil, 0, NI_NUMERICHOST
        ) == 0 else { return nil }

        return String(cString: buf)
    }
}
