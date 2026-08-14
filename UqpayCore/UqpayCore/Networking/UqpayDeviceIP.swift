import Foundation

/// Reports the device's own IP address for the confirm API's `ip_address`
/// field, which feeds 3DS risk assessment.
///
/// This is the address of the active network interface — behind NAT it is a
/// private address, which is still the honest client-side value. The SDK
/// never fabricates a public address: wrong data is worse for risk scoring
/// than a private one.
public enum UqpayDeviceIP {

    /// The device's current IP address, preferring Wi-Fi (`en0`) then
    /// cellular (`pdp_ip0`), IPv4 over IPv6. Nil when no interface is up.
    public static func current() -> String? {
        var addresses: [(interface: String, family: Int32, address: String)] = []

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let sa = interface.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }

            let name = String(cString: interface.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sa, socklen_t(sa.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            var address = String(cString: host)
            // Strip IPv6 scope suffixes like "%en0" and skip loopback/link-local.
            if let percent = address.firstIndex(of: "%") {
                address = String(address[..<percent])
            }
            if address == "127.0.0.1" || address == "::1" || address.hasPrefix("fe80") {
                continue
            }
            addresses.append((name, family, address))
        }

        let interfacePriority = ["en0", "pdp_ip0"]
        for name in interfacePriority {
            if let match = addresses.first(where: { $0.interface == name && $0.family == AF_INET }) {
                return match.address
            }
        }
        return addresses.first(where: { $0.family == AF_INET })?.address
            ?? addresses.first?.address
    }
}
