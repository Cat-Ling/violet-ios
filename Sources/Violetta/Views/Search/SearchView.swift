import SwiftUI

struct SearchView: View {
    var body: some View {
        NavigationStack {
            SearchContentView()
        }
    }
}

struct SearchContentView: View {
    @Environment(VioletClient.self) private var client
    var initialQuery: String? = nil
    @State private var query: String
    @State private var searchMode = 0 // 0: Standard, 1: AI, 2: Message
    @State private var articles: [Article] = []
    @State private var aiAnswer: String? = nil
    @State private var isLoading = false
    @State private var error: Error?
    @State private var isSearchPresented = false
    
    @State private var currentPage = 0
    @State private var canLoadMore = true
    @State private var isFetchingMore = false
    
    @State private var suggestions: [VioletClient.TagEntry] = []
    @State private var fetchSuggestionsTask: Task<Void, Never>? = nil
    
    @AppStorage("aiSearchEnabled") private var aiSearchEnabled = false
    @AppStorage("messageSearchEnabled") private var messageSearchEnabled = true
    @AppStorage("contentLanguage") private var contentLanguage = "all"
    @AppStorage("contextualSuggestionCounts") private var contextualSuggestionCounts = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]
    
    init(initialQuery: String? = nil) {
        self.initialQuery = initialQuery
        self._query = State(initialValue: initialQuery ?? "")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if aiSearchEnabled || messageSearchEnabled {
                Picker("Search Mode", selection: $searchMode) {
                    Text("Standard").tag(0)
                    if aiSearchEnabled { Text("AI").tag(1) }
                    if messageSearchEnabled { Text("Message").tag(2) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = error {
                    ErrorStateView(error: error) {
                        Task { await performSearch() }
                    }
                } else if articles.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else if articles.isEmpty {
                    ContentUnavailableView("Search Violetta", systemImage: "magnifyingglass", description: Text("Enter tags, artists, or text to search the database."))
                } else {
                    searchResultsView
                }
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, isPresented: $isSearchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search tags, artists, series...")
        .searchSuggestions {
            searchSuggestionsView
        }
            .onSubmit(of: .search) {
                suggestions = []
                fetchSuggestionsTask?.cancel()
                Task { await performSearch() }
            }
            .onReceive(AppStateManager.shared.searchTabDoubleTapped) { _ in
                isSearchPresented = true
            }
            .onChange(of: searchMode) {
                if !query.isEmpty {
                    Task { await performSearch() }
                }
            }
            .onChange(of: query) { _, newQuery in
                loadSuggestions(for: newQuery)
            }
        .onAppear {
            if !query.isEmpty && articles.isEmpty {
                Task { await performSearch() }
            }
        }
    }
    
    @ViewBuilder
    private var searchSuggestionsView: some View {
        if !suggestions.isEmpty && searchMode == 0 {
            ForEach(suggestions, id: \.self) { suggestion in
                HStack {
                    Text(suggestion.display)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(suggestion.contextualCount ?? suggestion.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .searchCompletion(completeQuery(with: suggestion.display))
            }
        }
    }
    
    @ViewBuilder
    private var searchResultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let answer = aiAnswer, searchMode == 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Insight")
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                        Text(answer)
                            .font(.subheadline)
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(articles) { article in
                        NavigationLink(destination: ArticleView(article: article)) {
                            GalleryCard(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                    }
                    .padding(.horizontal)
                    
                    if canLoadMore && searchMode == 0 && !articles.isEmpty {
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
            .padding(.vertical)
        }
    }
    
    private func performSearch() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            articles = []
            aiAnswer = nil
            return
        }
        
        isLoading = true
        error = nil
        aiAnswer = nil
        currentPage = 0
        canLoadMore = true
        
        do {
            if searchMode == 0 {
                let result = try await client.searchArticles(query: query, page: currentPage)
                self.articles = result.articles
                self.canLoadMore = result.articles.count == 30
            } else if searchMode == 1 {
                let response = try await client.fetchAiSearch(query: query)
                self.aiAnswer = response.answer
                let ids = response.results.compactMap { Int($0.articleId) }
                if ids.isEmpty {
                    self.articles = []
                } else {
                    self.articles = try await client.getArticlesBatch(ids: ids)
                }
                self.canLoadMore = false // AI search doesn't paginate
            } else if searchMode == 2 {
                let limit = UserDefaults.standard.integer(forKey: "messageSearchResultLimit")
                let safeLimit = limit > 0 ? limit : 100
                let response = try await client.fetchMessageSearch(query: query, limit: safeLimit)
                let ids = response.results.compactMap { $0.articleId }
                if ids.isEmpty {
                    self.articles = []
                } else {
                    self.articles = try await client.getArticlesBatch(ids: ids)
                }
                self.canLoadMore = false // Message search doesn't paginate directly here
            }
        } catch {
            self.error = error
        }
        isLoading = false
    }
    
    private func loadMore() async {
        guard canLoadMore, !isFetchingMore, searchMode == 0 else { return }
        isFetchingMore = true
        currentPage += 1
        
        do {
            let result = try await client.searchArticles(query: query, page: currentPage)
            if result.articles.isEmpty {
                canLoadMore = false
            } else {
                self.articles.append(contentsOf: result.articles)
                canLoadMore = result.articles.count == 30
            }
        } catch {
            currentPage -= 1
            print("Failed to load more: \(error)")
        }
        isFetchingMore = false
    }
    
    private func completeQuery(with newTag: String) -> String {
        var tokens = query.components(separatedBy: .whitespaces)
        if tokens.isEmpty { return newTag + " " }
        let lastToken = tokens.last!
        let prefix = lastToken.starts(with: "-") ? "-" : ""
        tokens[tokens.count - 1] = prefix + newTag
        return tokens.joined(separator: " ") + " "
    }
    
    private func loadSuggestions(for text: String) {
        fetchSuggestionsTask?.cancel()
        guard searchMode == 0 else {
            suggestions = []
            return
        }
        
        let tokens = text.components(separatedBy: .whitespaces)
        guard let lastToken = tokens.last, !lastToken.isEmpty else {
            suggestions = []
            return
        }
        
        var partial = String(lastToken)
        if partial.starts(with: "-") {
            partial = String(partial.dropFirst())
        }
        
        if partial.isEmpty {
            suggestions = []
            return
        }
        
        fetchSuggestionsTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            if Task.isCancelled { return }
            
            do {
                let previousTokens = tokens.dropLast().joined(separator: " ")
                let fetched = try await client.fetchSuggestions(
                    query: partial,
                    limit: 15,
                    filterLanguage: contentLanguage,
                    contextual: contextualSuggestionCounts,
                    baseTokens: previousTokens
                )
                if !Task.isCancelled {
                    self.suggestions = fetched
                }
            } catch {
                print("Failed to fetch suggestions: \(error)")
            }
        }
    }
}
