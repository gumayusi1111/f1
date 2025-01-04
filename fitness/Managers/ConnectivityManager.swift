import SwiftUI
import Network

class ConnectivityManager: ObservableObject {
    @Published private(set) var isOnline = true
    private var monitor: NWPathMonitor?
    
    init() {
        setupMonitor()
    }
    
    private func setupMonitor() {
        monitor = NWPathMonitor()
        monitor?.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor?.start(queue: DispatchQueue.global())
    }
    
    deinit {
        monitor?.cancel()
    }
} 