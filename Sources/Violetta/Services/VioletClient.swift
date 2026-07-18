import Foundation
import Nuke
import SwiftUI
import CryptoKit

enum VioletError: Error {
    case invalidServerURL
    case networkError(Error)
    case invalidResponse
    case decodingError(Error)
}

@MainActor
@Observable
class VioletClient {
    private let session: URLSession
    
    init() {
        self.session = URLSession.shared
    }
    
    private var baseURL: URL? {
        let savedURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        if savedURL.isEmpty { return nil }
        var cleanURL = savedURL
        if cleanURL.hasSuffix("/") { cleanURL.removeLast() }
        return URL(string: cleanURL + "/api")
    }
    
    private func applySearchFilters(to query: String) -> String {
        var modifiedQuery = query
        let contentLanguage = UserDefaults.standard.string(forKey: "contentLanguage") ?? "all"
        if contentLanguage != "all" {
            modifiedQuery += modifiedQuery.isEmpty ? "lang:\(contentLanguage)" : " lang:\(contentLanguage)"
        }
        
        let excludedTags = UserDefaults.standard.string(forKey: "excludedTags") ?? ""
        let tags = excludedTags.components(separatedBy: ",").filter({ !$0.isEmpty })
        if !tags.isEmpty {
            let excludeTags = tags.filter { !query.contains("-\($0)") }.map { "-\($0)" }
            if !excludeTags.isEmpty {
                let excludeStr = excludeTags.joined(separator: " ")
                modifiedQuery += modifiedQuery.isEmpty ? excludeStr : " " + excludeStr
            }
        }
        return modifiedQuery.trimmingCharacters(in: .whitespaces)
    }
    
    func searchArticles(query: String, page: Int = 0, pageSize: Int = 30) async throws -> ArticleSearchResult {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var components = URLComponents(url: base.appendingPathComponent("content/search"), resolvingAgainstBaseURL: true)!
        
        let finalQuery = applySearchFilters(to: query)
        
        components.queryItems = [
            URLQueryItem(name: "q", value: finalQuery),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        
        do {
            let (data, response) = try await session.data(from: components.url!)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw VioletError.invalidResponse
            }
            return try JSONDecoder().decode(ArticleSearchResult.self, from: data)
        } catch let error as DecodingError {
            print("Decoding Error in searchArticles: \(error)")
            throw VioletError.decodingError(error)
        } catch {
            throw VioletError.networkError(error)
        }
    }
    
    func fetchGalleryImages(id: Int) async throws -> ImageList {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        let url = base.appendingPathComponent("proxy/gallery/\(id)")
        
        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw VioletError.invalidResponse
            }
            return try JSONDecoder().decode(ImageList.self, from: data)
        } catch let error as DecodingError {
            print("Decoding Error in fetchGalleryImages: \(error)")
            throw VioletError.decodingError(error)
        } catch {
            throw VioletError.networkError(error)
        }
    }
    
    struct TagEntry: Codable, Hashable {
        let category: String
        let tag: String
        let display: String
        let count: Int
        let contextualCount: Int?
        
        var isExclusion: Bool {
            return category == "exclude" || tag.starts(with: "-")
        }
    }
    
    struct SuggestionsResponse: Codable {
        let suggestions: [TagEntry]
    }
    
    func fetchSuggestions(query: String, limit: Int = 20, filterLanguage: String? = nil, contextual: Bool = false, baseTokens: String? = nil) async throws -> [TagEntry] {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        
        let path = contextual ? "content/suggest/contextual" : "content/suggest"
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: true)!
        
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let filterLanguage = filterLanguage, filterLanguage != "all" {
            queryItems.append(URLQueryItem(name: "filterLanguage", value: filterLanguage))
        }
        if contextual, let b = baseTokens {
            queryItems.append(URLQueryItem(name: "base", value: b))
        }
        components.queryItems = queryItems
        
        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(SuggestionsResponse.self, from: data)
        return result.suggestions
    }
    
    func getDirectImageRequest(url: String, referer: String? = nil, width: CGFloat? = nil) -> ImageRequest? {
        var workingURL = url
        if workingURL.hasPrefix("//") {
            workingURL = "https:" + workingURL
        }
        
        var finalReferer = referer
        if workingURL.contains("exhentai.org") || workingURL.contains("e-hentai.org") || workingURL.contains("ehgt.org") {
            finalReferer = "https://e-hentai.org/"
        } else if finalReferer == nil && workingURL.contains("hitomi.la") {
            finalReferer = "https://hitomi.la/"
        }
        
        let pattern = "^(https?://)([a-z]+)\\.hitomi\\.la/"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(workingURL.startIndex..<workingURL.endIndex, in: workingURL)
        let rewritten = regex?.stringByReplacingMatches(in: workingURL, options: [], range: range, withTemplate: "$1$2.gold-usergeneratedcontent.net/") ?? workingURL
        
        guard let finalURL = URL(string: rewritten) else { return nil }
        var request = URLRequest(url: finalURL)
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let finalReferer = finalReferer {
            request.setValue(finalReferer, forHTTPHeaderField: "Referer")
        }
        
        var processors: [ImageProcessing] = []
        if let width = width {
            processors.append(ImageProcessors.Resize(width: width))
        }
        
        return ImageRequest(urlRequest: request, processors: processors)
    }
    
    func fetchThumbnailRequest(articleId: Int) async throws -> ImageRequest? {
        guard let base = baseURL else { return nil }
        let url = base.appendingPathComponent("proxy/thumbnail/\(articleId)")
        
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        
        struct ThumbnailResponse: Codable {
            let url: String
        }
        let thumbnail = try JSONDecoder().decode(ThumbnailResponse.self, from: data)
        return getDirectImageRequest(url: thumbnail.url, referer: "https://hitomi.la/reader/\(articleId).html", width: 400)
    }
    
    func triggerDownload(articleId: Int) async throws {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("downloads"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["articleId": String(articleId)]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw VioletError.invalidResponse
        }
    }
    
    func fetchIntensityTimeline(workId: Int) async throws -> IntensityTimeline {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        let url = base.appendingPathComponent("intensity/\(workId)")
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        
        return try JSONDecoder().decode(IntensityTimeline.self, from: data)
    }
    
    func fetchIntensityStatus() async throws -> IntensityTimelineStatus {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        let url = base.appendingPathComponent("intensity/status")
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        
        return try JSONDecoder().decode(IntensityTimelineStatus.self, from: data)
    }
    
    func fetchHistory(page: Int = 0, pageSize: Int = 30) async throws -> HistoryResponse {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var components = URLComponents(url: base.appendingPathComponent("history"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        
        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        return try JSONDecoder().decode(HistoryResponse.self, from: data)
    }
    
    struct InsertReadLogRequest: Codable {
        let Article: String
        let `Type`: Int
    }
    
    struct UpdateReadLogRequest: Codable {
        let LastPage: Int
        let DateTimeEnd: String?
    }
    
    func insertReadLog(articleId: Int, type: Int = 0) async throws -> Int {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("history"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = InsertReadLogRequest(Article: String(articleId), Type: type)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["Article": payload.Article, "Type": payload.Type])
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw VioletError.invalidResponse
        }
        
        struct InsertResponse: Codable {
            let Id: Int
        }
        return try JSONDecoder().decode(InsertResponse.self, from: data).Id
    }
    
    func updateReadLog(logId: Int, lastPage: Int) async throws {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("history/\(logId)"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let formatter = ISO8601DateFormatter()
        let payload = UpdateReadLogRequest(LastPage: lastPage, DateTimeEnd: formatter.string(from: Date()))
        request.httpBody = try JSONSerialization.data(withJSONObject: ["LastPage": payload.LastPage, "DateTimeEnd": payload.DateTimeEnd!])
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
            throw VioletError.invalidResponse
        }
    }
    
    func deleteHistory(logId: Int) async throws {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("history/\(logId)"))
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw VioletError.invalidResponse
        }
    }
    
    func clearHistory() async throws {
        var hasMore = true
        while hasMore {
            let response = try await fetchHistory(page: 0, pageSize: 100)
            if response.logs.isEmpty {
                hasMore = false
                break
            }
            
            await withTaskGroup(of: Void.self) { group in
                for log in response.logs {
                    group.addTask {
                        try? await self.deleteHistory(logId: log.id)
                    }
                }
            }
        }
    }
    
    func fetchLastPage(articleId: Int) async throws -> Int? {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        let url = base.appendingPathComponent("history/last-page/\(articleId)")
        
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        
        struct LastPageResponse: Codable {
            let lastPage: Int?
        }
        return try JSONDecoder().decode(LastPageResponse.self, from: data).lastPage
    }
    
    // MARK: - Bookmark Groups
    
    func fetchBookmarkGroups() async throws -> [BookmarkGroup] {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        let url = base.appendingPathComponent("bookmarks/groups")
        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw VioletError.invalidResponse
        }
        return try JSONDecoder().decode([BookmarkGroup].self, from: data)
    }
    
    func createBookmarkGroup(name: String, description: String? = nil) async throws -> Int {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("bookmarks/groups"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = ["Name": name]
        if let desc = description { body["Description"] = desc }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw VioletError.invalidResponse
        }
        
        let res = try JSONDecoder().decode([String: Int].self, from: data)
        return res["Id"] ?? -1
    }
    
    func deleteBookmarkGroup(id: Int) async throws {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("bookmarks/groups/\(id)"))
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw VioletError.invalidResponse
        }
    }
    
    
    func fetchBookmarkArticles(groupId: Int? = nil) async throws -> [BookmarkArticle] {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var components = URLComponents(url: base.appendingPathComponent("bookmarks/articles"), resolvingAgainstBaseURL: true)!
        if let groupId = groupId {
            components.queryItems = [URLQueryItem(name: "groupId", value: String(groupId))]
        }
        
        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        return try JSONDecoder().decode([BookmarkArticle].self, from: data)
    }
    
    func createBookmarkArticle(articleId: String, groupId: Int) async throws -> Int {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("bookmarks/articles"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["Article": articleId, "GroupId": groupId])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw VioletError.invalidResponse }
        let res = try JSONDecoder().decode([String: Int].self, from: data)
        return res["Id"] ?? -1
    }
    
    func deleteBookmarkArticle(id: Int) async throws {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("bookmarks/articles/\(id)"))
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw VioletError.invalidResponse }
    }
    
    func toggleBookmark(articleId: Int) async throws -> Bool {
        // Fetch current bookmarks to see if it's bookmarked, and if so, get its ID to delete it
        let bookmarks = try await fetchBookmarkArticles()
        
        if let existing = bookmarks.first(where: { Int($0.article ?? "") == articleId }) {
            // Already bookmarked, delete it
            guard let base = baseURL else { throw VioletError.invalidServerURL }
            var request = URLRequest(url: base.appendingPathComponent("bookmarks/articles/\(existing.id)"))
            request.httpMethod = "DELETE"
            
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw VioletError.invalidResponse
            }
            return false // Now unbookmarked
        } else {
            // Not bookmarked, create it
            guard let base = baseURL else { throw VioletError.invalidServerURL }
            var request = URLRequest(url: base.appendingPathComponent("bookmarks/articles"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let payload: [String: Any] = ["Article": String(articleId)]
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw VioletError.invalidResponse
            }
            return true // Now bookmarked
        }
    }
    
    func checkBookmark(articleId: Int) async throws -> Bool {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        let request = URLRequest(url: base.appendingPathComponent("bookmarks/articles/check/\(articleId)"))
        
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return false
        }
        
        struct CheckResponse: Codable {
            let bookmarked: Bool
        }
        return try JSONDecoder().decode(CheckResponse.self, from: data).bookmarked
    }
    
    func getArticlesBatch(ids: [Int]) async throws -> [Article] {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("content/batch"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["ids": ids]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        
        struct BatchResponse: Codable {
            let articles: [Article]
        }
        return try JSONDecoder().decode(BatchResponse.self, from: data).articles
    }
    
    func fetchHotView(period: String = "daily", offset: Int = 0, count: Int = 30) async throws -> [Int] {
        let defaultHost = "https://koromo.cc"
        let hostString = UserDefaults.standard.string(forKey: "developerServerURL") ?? defaultHost
        let host = hostString.isEmpty ? defaultHost : hostString
        guard let base = URL(string: host) else { throw VioletError.invalidServerURL }
        
        let salt = UserDefaults.standard.string(forKey: "hmacSalt") ?? ""
        let token = String(Int(Date().timeIntervalSince1970 * 1000))
        let input = salt.replacingOccurrences(of: "\\", with: "") + token
        let hash = SHA512.hash(data: Data(input.utf8))
        let valid = String(hash.compactMap { String(format: "%02x", $0) }.joined().prefix(7))
        
        var components = URLComponents(url: base.appendingPathComponent("api/v2/view"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "count", value: String(count)),
            URLQueryItem(name: "type", value: period)
        ]
        
        var request = URLRequest(url: components.url!)
        request.setValue(token, forHTTPHeaderField: "v-token")
        request.setValue(valid, forHTTPHeaderField: "v-valid")
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        
        struct HotResponse: Codable {
            let elements: [HotElement]
        }
        struct HotElement: Codable {
            let articleId: Int
            let count: Int
        }
        
        return try JSONDecoder().decode(HotResponse.self, from: data).elements.map { $0.articleId }
    }
    
    struct DownloadsResponse: Codable {
        let downloads: [DownloadRecord]
        let totalCount: Int
    }
    
    struct DownloadRecord: Codable, Identifiable {
        let id: Int
        let articleId: String
        let date: String
        let status: String
        let totalPages: Int?
        let downloadedPages: Int?
        let errorMessage: String?
        
        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case articleId = "Article"
            case date = "DateTime"
            case status = "Status"
            case totalPages = "TotalPages"
            case downloadedPages = "DownloadedPages"
            case errorMessage = "ErrorMessage"
        }
    }
    
    func deleteDownload(id: Int) async throws {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("downloads/\(id)"))
        request.httpMethod = "DELETE"
        
        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw VioletError.invalidResponse
        }
    }
    
    func fetchDownloads(page: Int = 0, pageSize: Int = 30) async throws -> DownloadsResponse {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var components = URLComponents(url: base.appendingPathComponent("downloads"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(pageSize))
        ]
        
        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        return try JSONDecoder().decode(DownloadsResponse.self, from: data)
    }
    
    struct AiSearchResponse: Codable {
        let query: String
        let results: [AiSearchResultItem]
        let answer: String?
    }

    struct AiSearchResultItem: Codable {
        let articleId: String
        let score: Double
        let description: String?
    }

    struct IntensityTimeline: Codable {
        let workId: Int
        let peaks: [[Double]] // index 0 is page, index 1 is score
        let interpolatedRanges: [[Int]]?
    }

    struct IntensityTimelineStatus: Codable {
        let indexedWorks: Int
        let error: String?
    }

    func fetchAiSearch(query: String, topK: Int = 5, mode: String = "fast") async throws -> AiSearchResponse {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var components = URLComponents(url: base.appendingPathComponent("ai-search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "top_k", value: String(topK)),
            URLQueryItem(name: "mode", value: mode)
        ]
        
        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        return try JSONDecoder().decode(AiSearchResponse.self, from: data)
    }
    
    struct MessageSearchResponse: Codable {
        let query: String
        let mode: String
        let total: Int
        let results: [MessageSearchResult]
    }

    struct MessageSearchResult: Codable {
        let articleId: Int
        let page: Int
    }
    
    func fetchMessageSearch(query: String, mode: String = "contains", limit: Int = 100) async throws -> MessageSearchResponse {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var components = URLComponents(url: base.appendingPathComponent("message-search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "mode", value: mode),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        
        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        return try JSONDecoder().decode(MessageSearchResponse.self, from: data)
    }
    
    struct UserActivity: Codable {
        let totals: ActivityTotals
        let days: [ActivityDay]
    }
    struct ActivityTotals: Codable {
        let reads: Int
        let bookmarks: Int
        let crops: Int
        let downloads: Int
        let total: Int
    }
    struct ActivityDay: Codable, Identifiable {
        let date: String
        let reads: Int
        let total: Int
        var id: String { date }
    }



    func fetchActivity() async throws -> UserActivity {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        let url = base.appendingPathComponent("activity")
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        return try JSONDecoder().decode(UserActivity.self, from: data)
    }

    struct AuthorSimilarityResponse: Codable {
        let similarAuthors: [AuthorSimilarityGroup]
    }
    struct AuthorSimilarityGroup: Codable, Identifiable {
        let authorKey: String
        let authorName: String
        let score: Double?
        let works: [Article]
        var id: String { authorKey }
    }

    func fetchAuthorSimilarity(author: String) async throws -> AuthorSimilarityResponse {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var components = URLComponents(url: base.appendingPathComponent("author-similarity"), resolvingAgainstBaseURL: true)!
        
        let contentLanguage = UserDefaults.standard.string(forKey: "contentLanguage") ?? "all"
        
        components.queryItems = [
            URLQueryItem(name: "author", value: author),
            URLQueryItem(name: "language", value: contentLanguage)
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        return try JSONDecoder().decode(AuthorSimilarityResponse.self, from: data)
    }
    
    func triggerSync() async throws {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("sync"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw VioletError.invalidResponse
        }
    }
    
    struct SuggestionCacheStatus: Codable {
        let built: Bool
        let counts: [String: Int]?
    }
    
    func fetchSuggestionCacheStatus() async throws -> SuggestionCacheStatus {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        let url = base.appendingPathComponent("content/suggest/status")
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw VioletError.invalidResponse
        }
        return try JSONDecoder().decode(SuggestionCacheStatus.self, from: data)
    }
    
    func rebuildSuggestionCache() async throws {
        guard let base = baseURL else { throw VioletError.invalidServerURL }
        var request = URLRequest(url: base.appendingPathComponent("content/suggest/rebuild"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            throw VioletError.invalidResponse
        }
    }
}
