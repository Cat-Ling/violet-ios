import SwiftUI
import Nuke

@main
struct ViolettaApp: App {
    @AppStorage("serverURL") private var serverURL: String = ""
    @AppStorage("imageCacheEnabled") private var imageCacheEnabled = true
    @AppStorage("imageCacheMaxSizeMB") private var imageCacheMaxSizeMB = 500
    @AppStorage("ignoreMediaSSLErrors") private var ignoreMediaSSLErrors = false
    
    @State private var client = VioletClient()
    
    init() {
        let isEnabled = UserDefaults.standard.object(forKey: "imageCacheEnabled") == nil ? true : UserDefaults.standard.bool(forKey: "imageCacheEnabled")
        let maxMB = UserDefaults.standard.object(forKey: "imageCacheMaxSizeMB") == nil ? 500 : UserDefaults.standard.integer(forKey: "imageCacheMaxSizeMB")
        let ignoreSSL = UserDefaults.standard.bool(forKey: "ignoreMediaSSLErrors")
        Self.configureNuke(enabled: isEnabled, maxMB: maxMB, ignoreSSL: ignoreSSL)
    }
    
    var body: some Scene {
        WindowGroup {
            if serverURL.isEmpty {
                OnboardingView()
            } else {
                AppShell()
                    .environment(client)
                    .environmentObject(AppStateManager.shared)
            }
        }
        .onChange(of: imageCacheEnabled) { _, newValue in
            Self.configureNuke(enabled: newValue, maxMB: imageCacheMaxSizeMB, ignoreSSL: ignoreMediaSSLErrors)
        }
        .onChange(of: imageCacheMaxSizeMB) { _, newValue in
            Self.configureNuke(enabled: imageCacheEnabled, maxMB: newValue, ignoreSSL: ignoreMediaSSLErrors)
        }
        .onChange(of: ignoreMediaSSLErrors) { _, newValue in
            Self.configureNuke(enabled: imageCacheEnabled, maxMB: imageCacheMaxSizeMB, ignoreSSL: newValue)
        }
    }
    
    static func configureNuke(enabled: Bool, maxMB: Int, ignoreSSL: Bool) {
        let dataLoader: any DataLoading
        if ignoreSSL {
            dataLoader = InsecureDataLoader()
        } else {
            dataLoader = DataLoader()
        }
        
        if enabled {
            let dataCache = try? DataCache(name: "com.project-violet.image-cache")
            dataCache?.sizeLimit = maxMB * 1024 * 1024
            
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            let memoryLimit = min(physicalMemory / 5, 500 * 1024 * 1024) // Up to 500MB or 20% of RAM
            ImageCache.shared.costLimit = Int(memoryLimit)
            
            ImagePipeline.shared = ImagePipeline {
                $0.dataLoader = dataLoader
                $0.dataCache = dataCache
                $0.imageCache = ImageCache.shared
                $0.isStoringPreviewsInMemoryCache = false
            }
        } else {
            ImagePipeline.shared = ImagePipeline {
                $0.dataLoader = dataLoader
                $0.dataCache = nil
                $0.imageCache = nil
            }
        }
    }
}

final class TaskCancellable: Nuke.Cancellable, @unchecked Sendable {
    let task: URLSessionTask
    init(task: URLSessionTask) { self.task = task }
    func cancel() { task.cancel() }
}

final class InsecureDataLoader: DataLoading, @unchecked Sendable {
    private let session: URLSession

    init() {
        let delegate = InsecureURLSessionDelegate()
        self.session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }

    func loadData(with request: URLRequest, didReceiveData: @escaping @Sendable (Data, URLResponse) -> Void, completion: @escaping @Sendable (Error?) -> Void) -> any Nuke.Cancellable {
        let task = session.dataTask(with: request) { data, response, error in
            if let data = data, let response = response {
                didReceiveData(data, response)
            }
            completion(error)
        }
        task.resume()
        return TaskCancellable(task: task)
    }
}

final class InsecureURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
