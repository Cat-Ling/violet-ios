import Foundation

enum PublishedValue: Codable, Equatable, Hashable {
    case string(String)
    case int(Int)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else {
            throw DecodingError.typeMismatch(PublishedValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or Int"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        }
    }
}

struct Article: Codable, Identifiable, Hashable {
    let id: Int
    let title: String
    let eHash: String?
    let type: String?
    let artists: String?
    let characters: String?
    let groups: String?
    let language: String?
    let series: String?
    let tags: String?
    let uploader: String?
    let published: PublishedValue?
    let files: Int?
    let `class`: String?
    let publishedEH: String?
    let thumbnail: String?
    let url: String?
    let existOnHitomi: Int?
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case title = "Title"
        case eHash = "EHash"
        case type = "Type"
        case artists = "Artists"
        case characters = "Characters"
        case groups = "Groups"
        case language = "Language"
        case series = "Series"
        case tags = "Tags"
        case uploader = "Uploader"
        case published = "Published"
        case files = "Files"
        case `class` = "Class"
        case publishedEH = "PublishedEH"
        case thumbnail = "Thumbnail"
        case url = "URL"
        case existOnHitomi = "ExistOnHitomi"
    }
    
    var normalizedTitle: String {
        return title
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
    
    var publishedDate: Date? {
        guard let published = published else { return nil }
        
        let ticksToSeconds = { (ticks: Int) -> Date in
            let unixTicks = ticks - 62_135_596_800_000_000
            let seconds = Double(unixTicks) / 10_000_000.0
            return Date(timeIntervalSince1970: seconds)
        }
        
        switch published {
        case .int(let ticks):
            return ticksToSeconds(ticks)
        case .string(let s):
            if let ticks = Int(s) {
                return ticksToSeconds(ticks)
            }
            return nil
        }
    }
}

struct ArticleSearchResult: Codable {
    let articles: [Article]
    let totalCount: Int
    let page: Int
    let pageSize: Int
}

struct ImageList: Codable {
    let urls: [String]
    let bigThumbnails: [String]
    let smallThumbnails: [String]
}
