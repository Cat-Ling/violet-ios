import Foundation

struct BookmarkGroup: Codable, Identifiable {
    let id: Int
    let name: String
    let dateTime: String
    let description: String?
    let color: Int?
    let gorder: Int
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case dateTime = "DateTime"
        case description = "Description"
        case color = "Color"
        case gorder = "Gorder"
    }
}

struct BookmarkArticle: Codable, Identifiable {
    let id: Int
    let article: String?
    let dateTime: String?
    let groupId: Int?
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case article = "Article"
        case dateTime = "DateTime"
        case groupId = "GroupId"
    }
}

enum ArtistType: Int, Codable {
    case artist = 0
    case group = 1
    case uploader = 2
    case series = 3
    case character = 4
}

struct BookmarkArtist: Codable, Identifiable {
    let id: Int
    let artist: String
    let isGroup: ArtistType
    let dateTime: String
    let groupId: Int
    
    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case artist = "Artist"
        case isGroup = "IsGroup"
        case dateTime = "DateTime"
        case groupId = "GroupId"
    }
}
