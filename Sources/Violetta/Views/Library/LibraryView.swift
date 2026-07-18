import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            LibraryContentView()
        }
    }
}

struct LibraryContentView: View {
    @Environment(VioletClient.self) private var client
    @State private var selectedTab = 1 // 0: History, 1: Bookmarks, 2: Downloads
    @State private var articles: [Article] = []
    @State private var downloads: [String: VioletClient.DownloadRecord] = [:]
    @State private var isLoading = false
    @State private var error: Error?
    
    @State private var historyLogs: [String: Int] = [:]
    @State private var showingClearHistoryAlert = false
    
    @State private var bookmarkGroups: [BookmarkGroup] = []
    @State private var selectedGroupId: Int? = nil
    @State private var showingNewGroupAlert = false
    @State private var newGroupName = ""
    @State private var newGroupDescription = ""
    
    @State private var currentPage = 0
    @State private var canLoadMore = true
    @State private var isFetchingMore = false
    
    @State private var searchQuery = ""
    @State private var isSearchPresented = false
    @State private var groupForInfo: BookmarkGroup?
    @State private var showingGroupInfo = false
    
    private var filteredArticles: [Article] {
        guard !searchQuery.isEmpty else { return articles }
        let queryTokens = searchQuery.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        return articles.filter { article in
            let title = article.title.lowercased()
            let tags = article.tags?.lowercased() ?? ""
            let artists = article.artists?.lowercased() ?? ""
            let series = article.series?.lowercased() ?? ""
            
            let fullText = "\(title) \(tags) \(artists) \(series)"
            
            return queryTokens.allSatisfy { token in
                if token.starts(with: "-") {
                    let exclusion = String(token.dropFirst())
                    return exclusion.isEmpty || !fullText.contains(exclusion)
                } else {
                    return fullText.contains(token)
                }
            }
        }
    }
    
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]
    
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    private var mainView: some View {
        VStack(spacing: 0) {
            Picker("Library Tab", selection: $selectedTab) {
                Text("Bookmarks").tag(1)
                Text("Downloads").tag(2)
                Text("History").tag(0)
            }
            .pickerStyle(.segmented)
            .padding()
            
            contentView
        }
        .navigationTitle("Library")
        .searchable(text: $searchQuery, isPresented: $isSearchPresented, prompt: searchPrompt)
        .searchSuggestions {
            searchSuggestionsView
        }
        .onChange(of: selectedTab) {
            Task { await loadData() }
        }
        .onReceive(timer) { _ in
            if selectedTab == 2 {
                Task {
                    do {
                        let response = try await client.fetchDownloads()
                        downloads = Dictionary(uniqueKeysWithValues: response.downloads.map { ($0.articleId, $0) })
                    } catch {}
                }
            }
        }
        .task {
            if articles.isEmpty {
                await loadData()
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            if !isSearchPresented && !newValue.isEmpty {
                searchQuery = ""
            }
        }
    }

    var body: some View {
        mainView
            .toolbar {
                if selectedTab == 0 && !articles.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showingClearHistoryAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .alert("Clear History", isPresented: $showingClearHistoryAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    Task {
                        do {
                            try await client.clearHistory()
                            await loadData()
                        } catch {
                            self.error = error
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to clear your entire reading history? This action cannot be undone.")
            }
            .alert("New Bookmark Folder", isPresented: $showingNewGroupAlert) {
                TextField("Name", text: $newGroupName)
                TextField("Description (optional)", text: $newGroupDescription)
                Button("Cancel", role: .cancel) {
                    newGroupName = ""
                    newGroupDescription = ""
                }
                Button("Create") {
                    Task {
                        if let _ = try? await client.createBookmarkGroup(name: newGroupName, description: newGroupDescription.isEmpty ? nil : newGroupDescription) {
                            bookmarkGroups = (try? await client.fetchBookmarkGroups()) ?? []
                        }
                        newGroupName = ""
                        newGroupDescription = ""
                    }
                }
            }
            .onChange(of: newGroupName) { _, newValue in
                if newValue.count > 50 {
                    newGroupName = String(newValue.prefix(50))
                }
            }
            .onChange(of: newGroupDescription) { _, newValue in
                if newValue.count > 150 {
                    newGroupDescription = String(newValue.prefix(150))
                }
            }
    }
    
    @ViewBuilder
    private var contentView: some View {
        if selectedTab == 1 {
            if isSearchPresented && !searchQuery.isEmpty {
                bookmarksSearchResultsView
            } else {
                bookmarkGroupsListView
            }
        } else {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = error {
                    ErrorStateView(error: error) {
                        Task { await loadData() }
                    }
                } else if articles.isEmpty {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: emptyIcon,
                        description: Text(emptyDescription)
                    )
                } else {
                    mangaGridView
                }
            }
        }
    }
    
    @ViewBuilder
    private var searchSuggestionsView: some View {
        if selectedTab == 1 && isSearchPresented && searchQuery.isEmpty {
            Text("Search by Prefix").font(.caption).foregroundStyle(.secondary)
            Button(action: { searchQuery = "manga: " }) {
                Label("manga:", systemImage: "book")
            }
            Button(action: { searchQuery = "folder: " }) {
                Label("folder:", systemImage: "folder")
            }
        }
    }
    
    private var searchState: (searchForFolders: Bool, searchForMangas: Bool, actualQuery: String) {
        var searchForFolders = true
        var searchForMangas = true
        var actualQuery = searchQuery.lowercased().trimmingCharacters(in: .whitespaces)
        
        if actualQuery.starts(with: "folder:") {
            searchForMangas = false
            actualQuery = String(actualQuery.dropFirst("folder:".count)).trimmingCharacters(in: .whitespaces)
        } else if actualQuery.starts(with: "manga:") {
            searchForFolders = false
            actualQuery = String(actualQuery.dropFirst("manga:".count)).trimmingCharacters(in: .whitespaces)
        }
        
        return (searchForFolders, searchForMangas, actualQuery)
    }

    @ViewBuilder
    private var bookmarksSearchResultsView: some View {
        let state = searchState
        let queryTokens = state.actualQuery.split(separator: " ").map { String($0) }
        
        let allArticles = state.searchForMangas ? articles.filter { article in
            if queryTokens.isEmpty { return true }
            let title = article.title.lowercased()
            let tags = article.tags?.lowercased() ?? ""
            let artists = article.artists?.lowercased() ?? ""
            let series = article.series?.lowercased() ?? ""
            
            let fullText = "\(title) \(tags) \(artists) \(series)"
            
            return queryTokens.allSatisfy { token in
                if token.starts(with: "-") {
                    let exclusion = String(token.dropFirst())
                    return exclusion.isEmpty || !fullText.contains(exclusion)
                } else {
                    return fullText.contains(token)
                }
            }
        } : []
        
        let allGroups = state.searchForFolders ? bookmarkGroups.filter { state.actualQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(state.actualQuery) } : []
        
        let showGroupLimit = state.searchForFolders && state.searchForMangas && allGroups.count > 3
        let displayedGroups = showGroupLimit ? Array(allGroups.prefix(3)) : allGroups
        
        ScrollView {
            VStack(spacing: 16) {
                if !displayedGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Folders")
                            .font(.headline)
                            .padding(.horizontal)
                            .padding(.top, 8)
                        
                        ForEach(displayedGroups) { group in
                            NavigationLink(destination: BookmarkGroupDetailView(group: group)) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(Color.accentColor)
                                        .font(.title3)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.name).font(.headline).lineLimit(1)
                                        Text(group.description?.isEmpty == false ? group.description! : "No description").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                        
                        if showGroupLimit {
                            Button {
                                searchQuery = "folder: " + state.actualQuery
                            } label: {
                                Text("See all \(allGroups.count) folders")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                        }
                    }
                }
                
                if !allArticles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mangas")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(allArticles) { article in
                                mangaGridItem(for: article)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                if displayedGroups.isEmpty && allArticles.isEmpty {
                    Text("No results found")
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                }
            }
            .padding(.bottom)
        }
    }
    
    @ViewBuilder
    private var bookmarkGroupsListView: some View {
        let filteredGroups = searchQuery.isEmpty ? bookmarkGroups : bookmarkGroups.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        
        List {
            ForEach(filteredGroups) { group in
                NavigationLink(destination: BookmarkGroupDetailView(group: group)) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.accentColor)
                            .font(.title3)
                            .frame(width: 30)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(.headline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            Text(group.description?.isEmpty == false ? group.description! : "No description")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
                .contextMenu {
                    Button {
                        groupForInfo = group
                        showingGroupInfo = true
                    } label: {
                        Label("Get Info", systemImage: "info.circle")
                    }
                    Button(role: .destructive) {
                        Task {
                            try? await client.deleteBookmarkGroup(id: group.id)
                            bookmarkGroups.removeAll(where: { $0.id == group.id })
                        }
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task {
                            try? await client.deleteBookmarkGroup(id: group.id)
                            bookmarkGroups.removeAll(where: { $0.id == group.id })
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            Button {
                showingNewGroupAlert = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .shadow(radius: 4, y: 2)
            }
            .padding()
        }
        .refreshable {
            bookmarkGroups = (try? await client.fetchBookmarkGroups()) ?? []
        }
        .alert("Folder Info", isPresented: $showingGroupInfo, presenting: groupForInfo) { group in
            Button("OK", role: .cancel) { }
        } message: { group in
            Text("Name: \(group.name)\nDescription: \(group.description ?? "None")\nID: \(group.id)")
        }
    }
    
    @ViewBuilder
    private var mangaGridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(filteredArticles) { article in
                    mangaGridItem(for: article)
                }
            }
            .padding()
            
            if canLoadMore && !articles.isEmpty {
                Color.clear
                    .frame(height: 50)
                    .onAppear {
                        Task { await loadMore() }
                    }
                if isFetchingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.bottom)
                }
            }
        }
        .refreshable {
            await loadData()
        }
    }
    
    @ViewBuilder
    private func mangaGridItem(for article: Article) -> some View {
        NavigationLink(destination: ArticleView(article: article)) {
            ZStack {
                GalleryCard(article: article)
                if selectedTab == 2, let dl = downloads[String(article.id)] {
                    if dl.status == "downloading" {
                        Color.black.opacity(0.6).clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(spacing: 8) {
                            if let dlPages = dl.downloadedPages, let total = dl.totalPages, total > 0 {
                                ZStack {
                                    Circle()
                                        .stroke(Color.white.opacity(0.3), lineWidth: 4)
                                    Circle()
                                        .trim(from: 0, to: CGFloat(dlPages) / CGFloat(total))
                                        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    Text("\(dlPages)/\(total)").font(.caption.bold()).foregroundStyle(.white)
                                }
                                .frame(width: 50, height: 50)
                            } else {
                                ProgressView().tint(.white).scaleEffect(1.5)
                            }
                        }
                    } else if dl.status == "completed" {
                        ZStack(alignment: .topLeading) {
                            Color.clear
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .green)
                                .font(.title2)
                                .padding(8)
                                .shadow(radius: 2)
                        }
                    } else if dl.status == "error" {
                        Color.black.opacity(0.6).clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .red)
                                .font(.largeTitle)
                            Text("Failed").font(.caption.bold()).foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if selectedTab == 0, let logId = historyLogs[String(article.id)] {
                Button(role: .destructive) {
                    Task {
                        do {
                            try await client.deleteHistory(logId: logId)
                            await loadData()
                        } catch {
                            self.error = error
                        }
                    }
                } label: {
                    Label("Remove from History", systemImage: "trash")
                }
            } else if selectedTab == 1 {
                Button(role: .destructive) {
                    Task {
                        do {
                            _ = try await client.toggleBookmark(articleId: article.id)
                            await loadData()
                        } catch {
                            self.error = error
                        }
                    }
                } label: {
                    Label("Remove Bookmark", systemImage: "bookmark.slash")
                }
            } else if selectedTab == 2, let dl = downloads[String(article.id)] {
                Button(role: .destructive) {
                    Task {
                        do {
                            try await client.deleteDownload(id: dl.id)
                            await loadData()
                        } catch {
                            self.error = error
                        }
                    }
                } label: {
                    Label("Delete Download", systemImage: "trash")
                }
            }
        }
    }

    private var searchPrompt: String {
        switch selectedTab {
        case 0: return "Search History"
        case 1: return "Search Folders"
        case 2: return "Search Downloads"
        default: return "Search"
        }
    }
    
    private var emptyTitle: String {
        switch selectedTab {
        case 0: return "No History"
        case 1: return "No Bookmarks"
        default: return "No Downloads"
        }
    }
    
    private var emptyIcon: String {
        switch selectedTab {
        case 0: return "clock"
        case 1: return "bookmark"
        default: return "arrow.down.circle"
        }
    }
    
    private var emptyDescription: String {
        switch selectedTab {
        case 0: return "Read some galleries to see them here."
        case 1: return "Bookmark some galleries to see them here."
        default: return "Downloaded galleries will appear here."
        }
    }
    
    private func loadData() async {
        isLoading = true
        error = nil
        currentPage = 0
        canLoadMore = true
        do {
            var ids: [Int] = []
            
            if selectedTab == 0 {
                let response = try await client.fetchHistory(page: currentPage)
                ids = response.logs.compactMap { Int($0.article) }
                historyLogs = Dictionary(uniqueKeysWithValues: response.logs.map { ($0.article, $0.id) })
                downloads = [:]
                canLoadMore = ids.count == 30
            } else if selectedTab == 1 {
                bookmarkGroups = (try? await client.fetchBookmarkGroups()) ?? []
                let allBookmarks = (try? await client.fetchBookmarkArticles()) ?? []
                ids = allBookmarks.compactMap { Int($0.article ?? "") }
                canLoadMore = false
            } else if selectedTab == 2 {
                let response = try await client.fetchDownloads()
                downloads = Dictionary(uniqueKeysWithValues: response.downloads.map { ($0.articleId, $0) })
                ids = response.downloads.compactMap { Int($0.articleId) }
                canLoadMore = false
            }
            
            if ids.isEmpty {
                self.articles = []
            } else {
                self.articles = try await client.getArticlesBatch(ids: ids)
            }
        } catch {
            self.error = error
        }
        isLoading = false
    }
    
    private func loadMore() async {
        guard canLoadMore, !isFetchingMore, selectedTab == 0 else { return }
        isFetchingMore = true
        currentPage += 1
        
        do {
            let response = try await client.fetchHistory(page: currentPage)
            let ids = response.logs.compactMap { Int($0.article) }
            if ids.isEmpty {
                canLoadMore = false
            } else {
                for log in response.logs {
                    historyLogs[log.article] = log.id
                }
                let newArticles = try await client.getArticlesBatch(ids: ids)
                self.articles.append(contentsOf: newArticles)
                canLoadMore = ids.count == 30
            }
        } catch {
            currentPage -= 1
            print("Failed to load more history: \(error)")
        }
        isFetchingMore = false
    }
}


struct BookmarkGroupDetailView: View {
    let group: BookmarkGroup
    @Environment(VioletClient.self) private var client
    
    @State private var bookmarkIds: [Int: Int] = [:]
    @State private var ids: [Int] = []
    @State private var articles: [Article] = []
    @State private var isLoading = true
    @State private var currentPage = 0
    @State private var canLoadMore = false
    @State private var isFetchingMore = false
    @State private var searchText = ""
    
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20)
    ]
    
    var filteredArticles: [Article] {
        if searchText.isEmpty { return articles }
        return articles.filter { $0.title.localizedCaseInsensitiveContains(searchText) == true }
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if articles.isEmpty {
                ContentUnavailableView("Empty Folder", systemImage: "folder", description: Text("There are no manga in this folder."))
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredArticles) { article in
                            NavigationLink(destination: ArticleView(article: article)) {
                                GalleryCard(article: article)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if let bId = bookmarkIds[article.id] {
                                    Button(role: .destructive) {
                                        Task {
                                            try? await client.deleteBookmarkArticle(id: bId)
                                            articles.removeAll(where: { $0.id == article.id })
                                            ids.removeAll(where: { $0 == article.id })
                                        }
                                    } label: {
                                        Label("Remove from Folder", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                    
                    if canLoadMore && !articles.isEmpty {
                        Color.clear
                            .frame(height: 50)
                            .onAppear {
                                Task { await loadMore() }
                            }
                        if isFetchingMore {
                            ProgressView().frame(maxWidth: .infinity).padding(.bottom)
                        }
                    }
                }
                .refreshable {
                    await loadData()
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search in \(group.name)")
        .task {
            if articles.isEmpty { await loadData() }
        }
    }
    
    private func loadData() async {
        do {
            isLoading = true
            let bookmarks = try await client.fetchBookmarkArticles(groupId: group.id)
            var bMap = [Int: Int]()
            for b in bookmarks {
                if let aIdStr = b.article, let aId = Int(aIdStr) {
                    bMap[aId] = b.id
                }
            }
            bookmarkIds = bMap
            ids = bookmarks.compactMap { Int($0.article ?? "") }
            currentPage = 0
            articles = []
            canLoadMore = true
            await fetchArticles()
            isLoading = false
        } catch {
            isLoading = false
        }
    }
    
    private func loadMore() async {
        guard canLoadMore, !isFetchingMore else { return }
        isFetchingMore = true
        currentPage += 1
        await fetchArticles()
        isFetchingMore = false
    }
    
    private func fetchArticles() async {
        guard currentPage * 30 < ids.count else {
            canLoadMore = false
            return
        }
        let chunk = Array(ids[currentPage * 30 ..< min((currentPage + 1) * 30, ids.count)])
        if chunk.isEmpty {
            canLoadMore = false
            return
        }
        do {
            let fetched = try await client.getArticlesBatch(ids: chunk)
            let ordered = chunk.compactMap { id in fetched.first(where: { $0.id == id }) }
            articles.append(contentsOf: ordered)
            canLoadMore = chunk.count == 30
        } catch {
            canLoadMore = false
        }
    }
}
