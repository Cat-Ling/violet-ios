import SwiftUI
import Combine
import Network

@MainActor
final class AppStateManager: ObservableObject {
    static let shared = AppStateManager()
    
    @Published var isOnline = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    // Combine publishers for global app events
    let searchTabDoubleTapped = PassthroughSubject<Void, Never>()
    let readerOpened = PassthroughSubject<Int, Never>() // Pass articleId
    
    private init() {
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in
                AppStateManager.shared.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
    }
}
