import SwiftUI

struct HomeView: View {
    @Environment(VioletClient.self) private var client
    @State private var feedType = 0 // 0: Latest, 1: Hot
    @State private var hotPeriod = "daily"
    @State private var articles: [Article] = []
    @State private var isLoading = true
    @State private var error: Error?
    
    @State private var currentPage = 0
    @State private var canLoadMore = true
    @State private var isFetchingMore = false
    
    @State private var searchQuery = ""
    @State private var isSearchPresented = false
    
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
    
    @AppStorage("developerMode") private var developerMode = false
    @AppStorage("hmacSalt") private var hmacSalt = ""
    
    private let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]
    
    private var isHotEnabled: Bool {
        developerMode && !hmacSalt.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isHotEnabled {
                    Picker("Feed", selection: $feedType) {
                        Text("Latest").tag(0)
                        Text("Hot").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                
                if feedType == 1 {
                    Picker("Timeframe", selection: $hotPeriod) {
                        Text("Daily").tag("daily")
                        Text("Weekly").tag("weekly")
                        Text("Monthly").tag("monthly")
                        Text("All Time").tag("alltime")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                
                Group {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = error {
                        ErrorStateView(error: error) {
                            Task { await fetchArticles() }
                        }
                    } else if articles.isEmpty {
                        ContentUnavailableView("No Content", systemImage: "xmark.circle")
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(filteredArticles) { article in
                                    NavigationLink(destination: ArticleView(article: article)) {
                                        GalleryCard(article: article)
                                    }
                                    .buttonStyle(.plain)
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
                            await fetchArticles()
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("Home")
            .searchable(text: $searchQuery, isPresented: $isSearchPresented, prompt: "Filter loaded feed...")
        }
        .task {
            if articles.isEmpty {
                await fetchArticles()
            }
        }
        .onChange(of: feedType) {
            Task { await fetchArticles() }
        }
        .onChange(of: hotPeriod) {
            if feedType == 1 {
                Task { await fetchArticles() }
            }
        }
    }
    
    private func fetchArticles() async {
        isLoading = true
        error = nil
        currentPage = 0
        canLoadMore = true
        
        do {
            if feedType == 0 {
                let result = try await client.searchArticles(query: "", page: currentPage)
                self.articles = result.articles
                self.canLoadMore = result.articles.count == 30
            } else {
                let ids = try await client.fetchHotView(period: hotPeriod, offset: currentPage * 30, count: 30)
                if ids.isEmpty {
                    self.articles = []
                    self.canLoadMore = false
                } else {
                    self.articles = try await client.getArticlesBatch(ids: ids)
                    self.canLoadMore = ids.count == 30
                }
            }
        } catch {
            self.error = error
        }
        isLoading = false
    }
    
    private func loadMore() async {
        guard canLoadMore, !isFetchingMore else { return }
        isFetchingMore = true
        currentPage += 1
        
        do {
            if feedType == 0 {
                let result = try await client.searchArticles(query: "", page: currentPage)
                if result.articles.isEmpty {
                    canLoadMore = false
                } else {
                    self.articles.append(contentsOf: result.articles)
                    canLoadMore = result.articles.count == 30
                }
            } else {
                let ids = try await client.fetchHotView(period: hotPeriod, offset: currentPage * 30, count: 30)
                if ids.isEmpty {
                    canLoadMore = false
                } else {
                    let newArticles = try await client.getArticlesBatch(ids: ids)
                    self.articles.append(contentsOf: newArticles)
                    canLoadMore = ids.count == 30
                }
            }
        } catch {
            currentPage -= 1
            print("Failed to load more: \(error)")
        }
        isFetchingMore = false
    }
}
