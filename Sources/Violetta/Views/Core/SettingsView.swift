import SwiftUI
import Nuke

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL: String = ""
    @AppStorage("themeMode") private var themeMode = "system"
    @AppStorage("themeColor") private var themeColor = "purple"
    
    @State private var selectedTab = 0 // 0: App, 1: Server
    
    // Server Settings
    @AppStorage("aiSearchEnabled") private var aiSearchEnabled = false
    @AppStorage("messageSearchEnabled") private var messageSearchEnabled = true
    @AppStorage("messageSearchResultLimit") private var messageSearchResultLimit = 100
    
    @AppStorage("imageCacheEnabled") private var imageCacheEnabled = true
    @AppStorage("imageCacheMaxSizeMB") private var imageCacheMaxSizeMB = 500
    @AppStorage("contextualSuggestionCounts") private var contextualSuggestionCounts = false
    
    @AppStorage("developerMode") private var developerMode = false
    @AppStorage("developerServerURL") private var developerServerURL = "https://koromo.cc"
    @AppStorage("hmacSalt") private var hmacSalt = ""
    
    @AppStorage("ignoreMediaSSLErrors") private var ignoreMediaSSLErrors = false

    @Environment(VioletClient.self) private var client
    @State private var testingMessageSearch = false
    @State private var messageSearchStatus: String? = nil
    
    @AppStorage("excludedTags") private var excludedTags: String = "female:snuff,female:gore"
    @AppStorage("contentLanguage") private var contentLanguage = "all"
    @AppStorage("imageCacheExpireDays") private var imageCacheExpireDays = 7
    
    @State private var cacheStatus: VioletClient.SuggestionCacheStatus? = nil
    @State private var isRebuildingCache = false
    @State private var cacheClearing = false
    @State private var isCalculatingStats = false
    @State private var newTag = ""
    @State private var currentCacheSizeMB: Double = 0
    @State private var currentCacheCount: Int = 0
    
    let themeColorsList: [(name: String, key: String)] = [
        ("Purple", "purple"), ("Amber", "amber"), ("Black", "black"),
        ("Blue", "blue"), ("Blue Grey", "blueGrey"), ("Brown", "brown"),
        ("Cyan", "cyan"), ("Deep Orange", "deepOrange"), ("Deep Purple", "deepPurple"),
        ("Green", "green"), ("Grey", "grey"), ("Indigo", "indigo"),
        ("Light Blue", "lightBlue"), ("Light Green", "lightGreen"), ("Lime", "lime"),
        ("Orange", "orange"), ("Pink", "pink"), ("Red", "red"),
        ("Teal", "teal"), ("Yellow", "yellow")
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Settings", selection: $selectedTab) {
                    Text("App").tag(0)
                    Text("Server").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()
                
                Form {
                    if selectedTab == 0 {
                        appSettings
                    } else {
                        serverSettings
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    @ViewBuilder
    private var appSettings: some View {
        Section("Theme") {
            Picker(selection: $themeMode) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            } label: {
                Label("Theme Mode", systemImage: "moon.circle.fill")
            }
            
            Picker(selection: $themeColor) {
                ForEach(themeColorsList, id: \.key) { color in
                    HStack {
                        Circle()
                            .fill(Color.themeColor(for: color.key))
                            .frame(width: 16, height: 16)
                        Text(color.name)
                    }
                    .tag(color.key)
                }
            } label: {
                Label("Theme Color", systemImage: "paintpalette.fill")
            }
        }



        Section("Network") {
            Toggle(isOn: $ignoreMediaSSLErrors) {
                Label("Ignore Media SSL Errors", systemImage: "lock.open.fill")
            }
            Text("Bypass SSL certificate validation when loading media from content delivery networks.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        
        Section(header: Text("Image Cache")) {
            Toggle(isOn: $imageCacheEnabled) {
                Label("Enable Image Cache", systemImage: "photo.stack.fill")
            }
            
            if imageCacheEnabled {
                Picker(selection: $imageCacheMaxSizeMB) {
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1024)
                    Text("2 GB").tag(2048)
                    Text("5 GB").tag(5120)
                    Text("10 GB").tag(10240)
                } label: {
                    Label("Max Cache Size", systemImage: "externaldrive.fill")
                }
                
                Picker(selection: $imageCacheExpireDays) {
                    Text("1 Day").tag(1)
                    Text("3 Days").tag(3)
                    Text("7 Days").tag(7)
                    Text("14 Days").tag(14)
                    Text("30 Days").tag(30)
                } label: {
                    Label("Cache Expiry", systemImage: "timer")
                }
                
                HStack {
                    Label("Cache Size", systemImage: "internaldrive.fill")
                    Spacer()
                    Text(String(format: "%.2f MB", currentCacheSizeMB))
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Label("Cached Items", systemImage: "photo.on.rectangle.angled")
                    Spacer()
                    Text("\(currentCacheCount)")
                        .foregroundStyle(.secondary)
                }
                
                Button(action: refreshCacheStats) {
                    HStack {
                        Label(isCalculatingStats ? "Calculating..." : "Refresh Stats", systemImage: "arrow.clockwise")
                            .foregroundStyle(isCalculatingStats ? .secondary : Color.primary)
                        Spacer()
                        if isCalculatingStats {
                            ProgressView()
                        }
                    }
                }
                .disabled(isCalculatingStats || cacheClearing)
                
                Button(action: clearImageCache) {
                    HStack {
                        Label(cacheClearing ? "Clearing..." : "Clear Cache", systemImage: "trash.fill")
                            .foregroundStyle(cacheClearing ? Color.secondary : Color.red)
                        Spacer()
                        if cacheClearing {
                            ProgressView()
                        }
                    }
                }
                .disabled(cacheClearing || isCalculatingStats)
            }
        }
        .task {
            refreshCacheStats()
        }
        
        Section(header: Text("Search Filters")) {
            Picker(selection: $contentLanguage) {
                Text("All").tag("all")
                Text("Korean").tag("korean")
                Text("English").tag("english")
                Text("Japanese").tag("japanese")
                Text("Chinese").tag("chinese")
            } label: {
                Label("Content Language", systemImage: "globe")
            }
        }
        
        Section(header: Text("Excluded Tags")) {
            List {
                ForEach(excludedTags.components(separatedBy: ",").filter({ !$0.isEmpty }), id: \.self) { tag in
                    Text(tag)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                var tags = excludedTags.components(separatedBy: ",").filter({ !$0.isEmpty })
                                if let index = tags.firstIndex(of: tag) {
                                    tags.remove(at: index)
                                    excludedTags = tags.joined(separator: ",")
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            
            HStack {
                TextField("Add excluded tag", text: $newTag)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") {
                    let tag = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !tag.isEmpty {
                        var tags = excludedTags.components(separatedBy: ",").filter({ !$0.isEmpty })
                        if !tags.contains(tag) {
                            tags.append(tag)
                            excludedTags = tags.joined(separator: ",")
                        }
                        newTag = ""
                    }
                }
                .disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        
        Section("About") {
            Link(destination: URL(string: "https://github.com/Cat-Ling/violet-ios")!) {
                Label("GitHub", systemImage: "link")
            }
            Link(destination: URL(string: "https://discord.com/invite/fqrtRxC")!) {
                Label("Discord", systemImage: "message.fill")
            }
            .disabled(true)
            .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var serverSettings: some View {
        Section(header: Text("Server Connection")) {
            HStack {
                Label("Server Address", systemImage: "server.rack")
                Spacer()
                TextField("https://...", text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
        }
        
        Section(header: Text("AI Search"), footer: Text("Requires violet-search microservice.")) {
            Toggle(isOn: $aiSearchEnabled) {
                Label("Enable AI Search", systemImage: "sparkles")
            }
        }
        
        Section("Message Search") {
            Toggle(isOn: $messageSearchEnabled) {
                Label("Enable Message Search", systemImage: "text.magnifyingglass")
            }
            
            if messageSearchEnabled {
                Picker(selection: $messageSearchResultLimit) {
                    Text("25").tag(25)
                    Text("50").tag(50)
                    Text("100").tag(100)
                    Text("200").tag(200)
                    Text("500").tag(500)
                } label: {
                    Label("Result Limit", systemImage: "list.number")
                }
                
                Button(action: testMessageSearch) {
                    HStack {
                        Label(testingMessageSearch ? "Testing..." : "Test Connection", systemImage: "network")
                        Spacer()
                        if testingMessageSearch {
                            ProgressView()
                        }
                    }
                }
                .disabled(testingMessageSearch)
                
                if let msg = messageSearchStatus {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.contains("Failed") ? .red : .green)
                }
            }
        }
        
        // Search Filters & Excluded Tags moved to appSettings
        Section(header: Text("Tag Autocomplete Cache")) {
            HStack {
                Label("Status", systemImage: "chart.bar.doc.horizontal")
                Spacer()
                if let status = cacheStatus {
                    Text(status.built ? "Built" : "Not Built")
                        .foregroundStyle(status.built ? .green : .red)
                } else {
                    ProgressView()
                        .onAppear(perform: loadSuggestionCacheStatus)
                }
            }
            
            if let status = cacheStatus, status.built {
                HStack {
                    Label("Total Tags", systemImage: "number")
                    Spacer()
                    let totalTags = status.counts?.values.reduce(0, +) ?? 0
                    Text("\(totalTags)")
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $contextualSuggestionCounts) {
                    Label("Contextual Suggestion Counts", systemImage: "text.badge.plus")
                }
                Text("Rank suggestions by the current search filters. This can slow autocomplete.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button(action: rebuildSuggestionCache) {
                HStack {
                    Label(isRebuildingCache ? "Building Cache..." : (cacheStatus?.built == true ? "Rebuild Cache" : "Build Cache"), systemImage: "wrench.and.screwdriver.fill")
                    Spacer()
                    if isRebuildingCache {
                        ProgressView()
                    }
                }
            }
            .disabled(isRebuildingCache)
        }
        
        Section(header: Text("Developer"), footer: Text("Enable developer mode to see Hot ranking tab.")) {
            Toggle(isOn: $developerMode) {
                Label("Enable Developer Mode", systemImage: "hammer.fill")
            }
            
            if developerMode {
                HStack {
                    Label("Server Host URL", systemImage: "network")
                    Spacer()
                    TextField("https://...", text: $developerServerURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                
                HStack {
                    Label("HMAC Salt", systemImage: "key.fill")
                    Spacer()
                    SecureField("...", text: $hmacSalt)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
    
    private func testMessageSearch() {
        Task {
            testingMessageSearch = true
            messageSearchStatus = nil
            do {
                _ = try await client.fetchMessageSearch(query: "test", limit: messageSearchResultLimit > 0 ? messageSearchResultLimit : 100)
                messageSearchStatus = "Connection OK"
            } catch {
                messageSearchStatus = "Connection Failed"
            }
            testingMessageSearch = false
        }
    }
    
    private func loadSuggestionCacheStatus() {
        Task {
            do {
                cacheStatus = try await client.fetchSuggestionCacheStatus()
            } catch {
                print("Failed to load suggestion cache status: \(error)")
            }
        }
    }
    
    private func rebuildSuggestionCache() {
        Task {
            isRebuildingCache = true
            do {
                try await client.rebuildSuggestionCache()
                loadSuggestionCacheStatus()
            } catch {
                print("Failed to rebuild suggestion cache: \(error)")
            }
            isRebuildingCache = false
        }
    }
    
    private func clearImageCache() {
        cacheClearing = true
        Task {
            ImageCache.shared.removeAll()
            ImagePipeline.shared.configuration.dataCache?.removeAll()
            try? await Task.sleep(nanoseconds: 500_000_000)
            refreshCacheStats()
            cacheClearing = false
        }
    }
    
    private func refreshCacheStats() {
        guard !isCalculatingStats else { return }
        isCalculatingStats = true
        
        Task {
            let (diskSize, diskCount) = await Task.detached(priority: .background) {
                var s: Int = 0
                var c: Int = 0
                if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
                    dataCache.flush()
                    s += dataCache.totalSize
                    c += dataCache.totalCount
                }
                return (s, c)
            }.value
            
            let totalS = diskSize + ImageCache.shared.totalCost
            let totalC = diskCount + ImageCache.shared.totalCount
            
            currentCacheSizeMB = Double(totalS) / (1024 * 1024)
            currentCacheCount = totalC
            isCalculatingStats = false
        }
    }
}
