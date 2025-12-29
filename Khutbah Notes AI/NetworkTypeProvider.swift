import Foundation
import Network

enum NetworkType: String {
    case wifi = "wifi"
    case cell = "cell"
    case unknown = "unknown"
}

final class NetworkTypeProvider {
    static let shared = NetworkTypeProvider()
    
    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkTypeProvider")
    private var currentType: NetworkType = .unknown
    
    private init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let type: NetworkType
            if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                type = .wifi
            } else if path.usesInterfaceType(.cellular) {
                type = .cell
            } else {
                type = .unknown
            }
            self?.currentType = type
        }
        monitor.start(queue: queue)
    }
    
    func currentNetworkType() -> NetworkType {
        currentType
    }
}
