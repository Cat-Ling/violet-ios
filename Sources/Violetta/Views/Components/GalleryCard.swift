import SwiftUI
import NukeUI
import Nuke

struct GalleryCard: View {
    let article: Article
    @Environment(VioletClient.self) private var client
    @State private var thumbnailRequest: ImageRequest?
    @State private var hasAttemptedFallback = false
    
    private var skeletonPlaceholder: some View {
        Color.secondary.opacity(0.1)
            .overlay {
                ProgressView()
            }
    }
    
    private var errorPlaceholder: some View {
        Color.secondary.opacity(0.1)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title2)
                    Text("Unavailable")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary.opacity(0.5))
            }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let request = thumbnailRequest {
                    LazyImage(request: request) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if state.error != nil {
                            errorPlaceholder
                        } else {
                            skeletonPlaceholder
                        }
                    }
                } else if let request = client.makeThumbnailRequest(from: article.thumbnail, articleId: article.id) {
                    LazyImage(request: request) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if state.error != nil {
                            if !hasAttemptedFallback {
                                skeletonPlaceholder
                                    .task {
                                        thumbnailRequest = try? await client.fetchThumbnailRequest(articleId: article.id)
                                        hasAttemptedFallback = true
                                    }
                            } else {
                                errorPlaceholder
                            }
                        } else {
                            skeletonPlaceholder
                        }
                    }
                } else {
                    if !hasAttemptedFallback {
                        skeletonPlaceholder
                            .task {
                                thumbnailRequest = try? await client.fetchThumbnailRequest(articleId: article.id)
                                hasAttemptedFallback = true
                            }
                    } else {
                        errorPlaceholder
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
