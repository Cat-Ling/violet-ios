import Foundation

enum ReadLogType: Int, Codable {
    case fromSearch = 0
    case fromBookmark = 1
}

struct ArticleReadLog: Codable, Identifiable {
    let id: Int
    let article: String
    let dateTimeStart: String
    let dateTimeEnd: String?
    let lastPage: Int
    let type: ReadLogType
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case article = "Article"
        case dateTimeStart = "DateTimeStart"
        case dateTimeEnd = "DateTimeEnd"
        case lastPage = "LastPage"
        case type = "Type"
    }
}

struct HistoryResponse: Codable {
    let logs: [ArticleReadLog]
    let totalCount: Int
    let page: Int
    let pageSize: Int
}
