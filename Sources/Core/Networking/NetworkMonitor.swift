//
//  NetworkMonitor.swift
//  XyecocMail
//
//  NWPathMonitor wrapper. Publishes connectivity state for UI banners
//  and fires an auto-retry callback when the connection is restored.
//

import Foundation
import Network
import Combine

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true

    /// Callers can subscribe to know when connectivity is restored.
    let restored = PassthroughSubject<Void, Never>()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.xyecoc.mail.netmon", qos: .utility)
    private var wasDisconnected = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let connected = (path.status == .satisfied)
                let previouslyDisconnected = self.wasDisconnected

                self.isConnected = connected
                self.wasDisconnected = !connected

                if connected && previouslyDisconnected {
                    self.restored.send()
                }
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
