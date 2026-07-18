import SwiftUI
import NukeUI
import Nuke

struct GalleryCard: View {
    let article: Article
    @Environment(VioletClient.self) private var client
    @State private var thumbnailRequest: ImageRequest?
    @State private var isDownloading = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                Color.secondary.opacity(0.1)
                
                if let request = thumbnailRequest {
                    LazyImage(request: request) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else if state.error != nil {
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
                } else {
                    ProgressView()
                        .task {
                            thumbnailRequest = try? await client.fetchThumbnailRequest(articleId: article.id)
                        }
                }
            }
            .aspectRatio(0.7, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                if let files = article.files {
                    Text("\(files) p")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }
            
            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                
                if let artists = article.artists {
                    Text(artists)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        }
    }
}
