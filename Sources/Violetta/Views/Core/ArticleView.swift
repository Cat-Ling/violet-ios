import SwiftUI
import NukeUI
import Nuke

struct ArticleView: View {
    let article: Article
    @Environment(VioletClient.self) private var client
    @State private var isDownloading = false
    @State private var thumbnailRequest: ImageRequest?
    @State private var isBookmarked = false
    @State private var showingBookmarkSheet = false
    @State private var isBookmarking = false
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var lastPage: Int? = nil
    @AppStorage("themeColor") private var themeColor = "purple"
    
    private var skeletonPlaceholder: some View {
        Color.secondary.opacity(0.1)
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .overlay { ProgressView() }
    }
    
    private var errorPlaceholder: some View {
        Color.secondary.opacity(0.1)
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.largeTitle)
                    Text("Cover Unavailable")
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary.opacity(0.5))
            }
    }
    
    @State private var hasAttemptedFallback = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Large Cover
                if let request = thumbnailRequest {
                    LazyImage(request: request) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        } else if state.error != nil {
                            errorPlaceholder
                        } else {
                            skeletonPlaceholder
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .shadow(radius: 8)
                } else if let request = client.makeThumbnailRequest(from: article.thumbnail, articleId: article.id) {
                    LazyImage(request: request) { state in
                        if let image = state.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                    .shadow(radius: 8)
                } else {
                    if !hasAttemptedFallback {
                        skeletonPlaceholder
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            .shadow(radius: 8)
                            .task {
                                thumbnailRequest = try? await client.fetchThumbnailRequest(articleId: article.id)
                                hasAttemptedFallback = true
                            }
                    } else {
                        errorPlaceholder
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                            .shadow(radius: 8)
                    }
                }
                
                // Title
                Text(article.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                // Extra Info block
                VStack(alignment: .leading, spacing: 10) {
                    Text("ID: \(article.id)")
                    if let published = article.published {
                        let pubString: String = {
                            switch published {
                            case .string(let s): return s
                            case .int(let i): return String(i)
                            }
                        }()
                        Text("Published: \(pubString)")
                    }
                    if let type = article.type {
                        HStack {
                            Text("Type:")
                            NavigationLink(destination: SearchContentView(initialQuery: "type:\(type.replacingOccurrences(of: " ", with: "_"))")) {
                                TagChip(text: type, color: Color.Tag.generic)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let language = article.language {
                        HStack {
                            Text("Language:")
                            NavigationLink(destination: SearchContentView(initialQuery: "lang:\(language.replacingOccurrences(of: " ", with: "_"))")) {
                                TagChip(text: language, color: Color.Tag.generic)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let uploader = article.uploader {
                        HStack {
                            Text("Uploader:")
                            NavigationLink(destination: SearchContentView(initialQuery: "uploader:\(uploader)")) {
                                TagChip(text: uploader, color: Color.Tag.generic)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let classType = article.`class` {
                        HStack {
                            Text("Class:")
                            NavigationLink(destination: SearchContentView(initialQuery: "class:\(classType.replacingOccurrences(of: " ", with: "_"))")) {
                                TagChip(text: classType, color: Color.Tag.generic)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let files = article.files { 
                        Text("Files: \(files) pages")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                
                // Metadata Tags
                VStack(alignment: .leading, spacing: 16) {
                    if let artists = article.artists {
                        TagRow(title: "Artists", prefix: "artist:", tags: artists, color: Color.Tag.artist)
                    }
                    if let groups = article.groups {
                        TagRow(title: "Groups", prefix: "group:", tags: groups, color: Color.Tag.group)
                    }
                    if let characters = article.characters {
                        TagRow(title: "Characters", prefix: "character:", tags: characters, color: Color.Tag.character)
                    }
                    if let series = article.series {
                        TagRow(title: "Series", prefix: "series:", tags: series, color: Color.Tag.series)
                    }
                    if let tags = article.tags {
                        let parsedTags = parseTags(tags)
                        TagRow(title: "Tags", tagItems: parsedTags)
                    }
                }
                .padding(.horizontal)
                
                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .navigationBarTitleDisplayMode(.inline)
        // Toolbar with Read / Download Buttons
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        isDownloading = true
                        do {
                            try await client.triggerDownload(articleId: article.id)
                            toastMessage = "Download queued."
                        } catch {
                            toastMessage = "Download failed: \(error.localizedDescription)"
                            print("Download failed: \(error)")
                        }
                        isDownloading = false
                        withAnimation {
                            showingToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                showingToast = false
                            }
                        }
                    }
                } label: {
                    if isDownloading {
                        ProgressView()
                    } else {
                        Image(systemName: "icloud.and.arrow.down")
                    }
                }
                .disabled(isDownloading)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 0) {
                NavigationLink(destination: ViewerView(articleId: article.id)) {
                    VStack(spacing: 2) {
                        Text("Read")
                            .font(.headline)
                            
                        if let files = article.files {
                            let current = lastPage ?? 0
                            if current == 0 {
                                Text("Unread")
                                    .font(.caption2)
                                    .opacity(0.8)
                            } else if current >= files - 1 {
                                Text("Finished")
                                    .font(.caption2)
                                    .opacity(0.8)
                            } else {
                                Text("\(current + 1) / \(files)")
                                    .font(.caption2)
                                    .opacity(0.8)
                            }
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                }
                
                Divider()
                    .overlay(Color.white.opacity(0.4))
                    .frame(height: 24)
                
                Button {
                    showingBookmarkSheet = true
                } label: {
                    ZStack {
                        if isBookmarking {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.headline.weight(.bold))
                                .imageScale(.large)
                                .scaleEffect(x: 1.15, y: 0.9)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 56)
                    .padding(.vertical, 16)
                }
            }
            .background(Color.themeColor(for: themeColor))
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
            .padding(.bottom, 16)
        }
        .overlay(alignment: .top) {
            if showingToast {
                Text(toastMessage)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            do {
                isBookmarked = try await client.checkBookmark(articleId: article.id)
            } catch {}
            do {
                lastPage = try await client.fetchLastPage(articleId: article.id)
            } catch {}
        }
        .sheet(isPresented: $showingBookmarkSheet) {
            BookmarkGroupsSheet(articleId: article.id)
                .onDisappear {
                    Task {
                        isBookmarked = (try? await client.checkBookmark(articleId: article.id)) ?? false
                    }
                }
        }
    }
    
    // The backend stores tags as "female:big breasts|male:shota" etc.
    private func parseTags(_ tags: String) -> [(text: String, color: Color, query: String)] {
        let items = tags.split(separator: "|")
        return items.map { item in
            let parts = item.split(separator: ":", maxSplits: 1)
            let category = parts.first?.lowercased() ?? ""
            let text = parts.count > 1 ? String(parts[1]) : String(item)
            
            let color: Color
            var query = String(item)
            
            if category == "female" { 
                color = Color.Tag.female 
            } else if category == "male" { 
                color = Color.Tag.male 
            } else { 
                color = Color.Tag.generic 
                if parts.count == 1 {
                    query = "tag:\(item)"
                }
            }
            
            return (text: text, color: color, query: query.replacingOccurrences(of: " ", with: "_"))
        }
    }
}

// Reusable component for the chip rows
struct TagRow: View {
    let title: String
    var prefix: String = ""
    var tags: String? = nil
    var tagItems: [(text: String, color: Color, query: String)]? = nil
    var color: Color = Color.Tag.generic
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            
            let layout = FlowLayout(spacing: 8)
            
            layout {
                if let tagItems = tagItems {
                    ForEach(tagItems, id: \.text) { item in
                        NavigationLink(destination: SearchContentView(initialQuery: item.query)) {
                            TagChip(text: item.text, color: item.color)
                        }
                        .buttonStyle(.plain)
                    }
                } else if let tags = tags {
                    let split = tags.split(separator: "|").map(String.init)
                    ForEach(split, id: \.self) { text in
                        let formattedQuery = "\(prefix)\(text)".replacingOccurrences(of: " ", with: "_")
                        NavigationLink(destination: SearchContentView(initialQuery: formattedQuery)) {
                            TagChip(text: text, color: color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct BookmarkGroupsSheet: View {
    let articleId: Int
    @Environment(VioletClient.self) private var client
    @Environment(\.dismiss) private var dismiss
    
    @State private var groups: [BookmarkGroup] = []
    @State private var articleBookmarks: [BookmarkArticle] = []
    @State private var isLoading = true
    
    @State private var showingNewGroupAlert = false
    @State private var newGroupName = ""
    @State private var newGroupDescription = ""
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView()
                } else {
                    let filteredGroups = searchText.isEmpty ? groups : groups.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
                    ForEach(filteredGroups) { group in
                        groupRow(for: group)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search folders")
            .navigationTitle("Save to...")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New Folder") {
                        showingNewGroupAlert = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await load()
            }
            .alert("New Folder", isPresented: $showingNewGroupAlert) {
                TextField("Name", text: $newGroupName)
                TextField("Description (optional)", text: $newGroupDescription)
                Button("Cancel", role: .cancel) {
                    newGroupName = ""
                    newGroupDescription = ""
                }
                Button("Create") {
                    Task {
                        if let _ = try? await client.createBookmarkGroup(name: newGroupName, description: newGroupDescription.isEmpty ? nil : newGroupDescription) {
                            await load()
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
    }
    
    @ViewBuilder
    private func groupRow(for group: BookmarkGroup) -> some View {
        let isSelected = articleBookmarks.contains { $0.groupId == group.id || ($0.groupId == nil && group.id == 1) }
        Button {
            toggleGroup(group: group, isSelected: isSelected)
        } label: {
            HStack {
                Text(group.name)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "bookmark.fill")
                        .font(.title2)
                        .scaleEffect(x: 1.15, y: 0.9)
                        .foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "bookmark")
                        .font(.title2)
                        .scaleEffect(x: 1.15, y: 0.9)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func load() async {
        do {
            async let fetchGroups = client.fetchBookmarkGroups()
            async let fetchBookmarks = client.fetchBookmarkArticles()
            
            groups = try await fetchGroups
            let allBookmarks = try await fetchBookmarks
            
            let articleIdStr = String(articleId)
            articleBookmarks = allBookmarks.filter { $0.article == articleIdStr }
            isLoading = false
        } catch {
            print("Failed to load bookmark groups: \(error)")
        }
    }
    
    private func toggleGroup(group: BookmarkGroup, isSelected: Bool) {
        Task {
            if isSelected {
                if let bm = articleBookmarks.first(where: { $0.groupId == group.id || ($0.groupId == nil && group.id == 1) }) {
                    try? await client.deleteBookmarkArticle(id: bm.id)
                    articleBookmarks.removeAll(where: { $0.id == bm.id })
                }
            } else {
                if let newId = try? await client.createBookmarkArticle(articleId: String(articleId), groupId: group.id) {
                    let newBm = BookmarkArticle(id: newId, article: String(articleId), dateTime: nil, groupId: group.id)
                    articleBookmarks.append(newBm)
                }
            }
        }
    }
}

struct TagChip: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// Simple FlowLayout for iOS 18 (Using native Layout protocol)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let point = result.points[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var points: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var rowHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += rowHeight + spacing
                    rowHeight = 0
                }
                points.append(CGPoint(x: currentX, y: currentY))
                rowHeight = max(rowHeight, size.height)
                currentX += size.width + spacing
            }
            size = CGSize(width: maxWidth, height: currentY + rowHeight)
        }
    }
}
