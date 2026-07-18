import SwiftUI
import NukeUI
import Nuke

struct ViewerView: View {
    let articleId: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(VioletClient.self) private var client
    @StateObject private var settings = ReaderSettings.shared
    
    @State private var imageList: ImageList?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var isControlsVisible = true
    @State private var currentPage = 0
    @State private var showingSettings = false
    @State private var readLogId: Int?
    @State private var previousPage: Int = 0
    @State private var jumpToPage: Int? = nil
    @State private var scrolledID: Int? = nil
    @State private var isScrubbing = false
    @State private var sliderValue: Double = 0
    @State private var aspectRatios: [Int: CGFloat] = [:]
    @State private var progressSyncTask: Task<Void, Never>? = nil
    @State private var intensityTimeline: VioletClient.IntensityTimeline? = nil
    
    var body: some View {
        ZStack {
            (settings.useDarkBackground ? Color.black : Color.white)
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else if let error = error {
                ErrorStateView(error: error) {
                    Task { await fetchImages() }
                }
            } else if let imageList = imageList {
                if settings.direction == .vertical {
                    verticalReader(urls: imageList.urls)
                } else {
                    horizontalReader(urls: imageList.urls)
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if let imageList = imageList {
                scrubberControls(urls: imageList.urls)
                    .opacity(isControlsVisible ? 1 : 0)
                    .offset(y: isControlsVisible ? 0 : 80)
                    .animation(.easeInOut(duration: 0.2), value: isControlsVisible)
                    .zIndex(10)
            }
        }
        .overlay(alignment: .top) {
            customTopBar
                .offset(y: isControlsVisible && !isScrubbing ? 0 : -100)
                .opacity(isControlsVisible && !isScrubbing ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isControlsVisible)
                .animation(.easeInOut(duration: 0.2), value: isScrubbing)
                .zIndex(12)
        }
        .overlay(alignment: .bottom) {
            if let imageList = imageList {
                Text("\(currentPage + 1) / \(imageList.urls.count)")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .padding(.bottom, 120) // Push high above the thumb/slider
                    .opacity(isScrubbing ? 1 : 0)
                    .scaleEffect(isScrubbing ? 1 : 0.8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isScrubbing)
                    .zIndex(11)
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .persistentSystemOverlays(isControlsVisible ? .automatic : .hidden)
        .persistentSystemOverlays(isControlsVisible ? .automatic : .hidden)
        .statusBarHidden(!isControlsVisible)
        .task {
            if imageList == nil {
                await fetchImages()
            }
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsView()
                .presentationDetents([.medium, .large])
        }
        .onChange(of: currentPage) {
            updateProgress()
        }
        .onDisappear {
            progressSyncTask?.cancel()
            if let id = readLogId {
                let finalPage = currentPage
                Task {
                    try? await client.updateReadLog(logId: id, lastPage: finalPage)
                }
            }
            ImageCache.shared.removeAll()
        }
    }
    
    @ViewBuilder
    private func verticalReader(urls: [String]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: settings.pagePadding) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { index, urlString in
                        readerImage(urlString: urlString, index: index)
                            .id(index)
                    }
                    
                    // Bottom padding so the last image isn't flush with the screen edge
                    Color.clear
                        .frame(height: UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 30)
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrolledID, anchor: .center)
            .onChange(of: scrolledID) { oldValue, newValue in
                if let newId = newValue, jumpToPage == nil {
                    currentPage = newId
                }
            }
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                return geo.contentOffset.y
            } action: { oldValue, newValue in
                guard settings.fullscreenMode else { return }
                guard !isScrubbing else { return } // Prevent scrubber jumps from hiding the UI
                
                // Ignore small deltas to avoid reacting to layout-induced offset shifts
                let delta = newValue - oldValue
                guard abs(delta) > 2 else { return }
                
                if newValue < -10 && !isControlsVisible {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isControlsVisible = true
                    }
                } else if delta > 5 && isControlsVisible && newValue > 0 {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isControlsVisible = false
                    }
                } else if delta < -5 && !isControlsVisible {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isControlsVisible = true
                    }
                }
            }
            .onChange(of: jumpToPage) { _, newPage in
                if let newPage = newPage {
                    if isScrubbing {
                        proxy.scrollTo(newPage, anchor: .top)
                    } else {
                        withAnimation {
                            proxy.scrollTo(newPage, anchor: .top)
                        }
                    }
                    jumpToPage = nil
                }
            }
            .onAppear {
                if let newPage = jumpToPage {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo(newPage, anchor: .top)
                        jumpToPage = nil
                    }
                }
            }
        }
        .onTapGesture {
            toggleControls()
        }
    }
    
    @ViewBuilder
    private func horizontalReader(urls: [String]) -> some View {
        // TabView for LeftToRight or RightToLeft
        TabView(selection: $currentPage) {
            ForEach(Array(urls.enumerated()), id: \.offset) { index, urlString in
                readerImage(urlString: urlString, index: index)
                    .tag(index)
                    .rotation3DEffect(
                        .degrees(settings.direction == .rightToLeft ? 180 : 0),
                        axis: (x: 0, y: 1, z: 0)
                    )
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .rotation3DEffect(
            .degrees(settings.direction == .rightToLeft ? 180 : 0),
            axis: (x: 0, y: 1, z: 0)
        )
        .onTapGesture { location in
            handleTapToNavigate(location: location, maxPages: urls.count)
        }
    }
    
    private func handleTapToNavigate(location: CGPoint, maxPages: Int) {
        if !settings.tapToNavigate {
            toggleControls()
            return
        }
        
        let screenWidth = UIScreen.main.bounds.width
        let tapRegion = location.x / screenWidth
        
        var goNext = false
        var goPrev = false
        
        if tapRegion < 0.3 {
            // Left
            if settings.direction == .rightToLeft { goNext = true } else { goPrev = true }
        } else if tapRegion > 0.7 {
            // Right
            if settings.direction == .rightToLeft { goPrev = true } else { goNext = true }
        } else {
            // Center
            toggleControls()
            return
        }
        
        if settings.invertTapToNavigate {
            swap(&goNext, &goPrev)
        }
        
        withAnimation {
            if goNext && currentPage < maxPages - 1 {
                currentPage += 1
            } else if goPrev && currentPage > 0 {
                currentPage -= 1
            }
        }
    }
    
    @ViewBuilder
    private func readerImage(urlString: String, index: Int) -> some View {
        let multiplier = settings.renderQuality / 100.0
        let deviceWidth: CGFloat? = multiplier >= 2.0 ? nil : UIScreen.main.bounds.width * UIScreen.main.scale * multiplier
        if let request = client.getDirectImageRequest(url: urlString, referer: "https://hitomi.la/reader/\(articleId).html", width: deviceWidth) {
            let width = UIScreen.main.bounds.width
            let cachedHeight = aspectRatios[index] != nil ? width / aspectRatios[index]! : nil
            
            LazyImage(request: request) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: settings.scaleType == .fit ? .fit : .fill)
                        .grayscale(settings.useGrayscale ? 1.0 : 0.0)
                        .extensionColorInvert(settings.useColorInvert)
                        .onAppear {
                            if aspectRatios[index] == nil, let uiImage = state.imageContainer?.image {
                                let ratio = uiImage.size.width / uiImage.size.height
                                aspectRatios[index] = ratio
                            }
                        }
                } else if state.error != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, minHeight: cachedHeight ?? 400)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: cachedHeight ?? 400)
                }
            }
            .frame(height: cachedHeight)
        }
    }
    
    private func toggleControls() {
        if !settings.fullscreenMode { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isControlsVisible.toggle()
        }
    }
    
    @ViewBuilder
    private func scrubberControls(urls: [String]) -> some View {
        VStack(spacing: 8) {
            Text("\(currentPage + 1) / \(urls.count)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                .opacity(isScrubbing ? 0 : 1)
            
            if let timeline = intensityTimeline {
                IntensityGraphView(timeline: timeline, totalPages: urls.count, isScrubbing: isScrubbing)
                    .padding(.horizontal, 10)
                    .padding(.bottom, -12)
            }
            
            let total = Double(max(0, urls.count - 1))
            ReaderSlider(
                value: Binding(
                    get: { isScrubbing ? sliderValue : Double(currentPage) },
                    set: { newValue in
                        sliderValue = newValue
                        let newPage = Int(round(newValue))
                        if newPage != currentPage {
                            currentPage = newPage
                            if settings.direction == .vertical {
                                jumpToPage = newPage
                            }
                        }
                    }
                ),
                isScrolling: $isScrubbing,
                range: 0...total
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        // Extra bottom padding to account for the home indicator / safe area
        .padding(.bottom, UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 32)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(isScrubbing ? 0 : 1)
                .ignoresSafeArea()
        )
        .overlay(alignment: .top) {
            Divider().opacity(isScrubbing ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {} // Swallow taps so they don't trigger reader navigation/controls
        .animation(.easeInOut(duration: 0.2), value: isScrubbing)
        .onDisappear {
            // Explicitly purge the in-memory RAM cache when closing a manga.
            // This prevents out-of-memory (JetSam) crashes when reading multiple mangas in a single session.
            ImageCache.shared.removeAll()
        }
    }
    
    private func fetchImages() async {
        isLoading = true
        error = nil
        do {
            self.imageList = try await client.fetchGalleryImages(id: articleId)
            
            // Automatically resume previous reading progress
            if let last = try? await client.fetchLastPage(articleId: articleId), last > 0 {
                previousPage = last
                if settings.direction == .vertical {
                    jumpToPage = last
                } else {
                    currentPage = last
                }
            }
            
            // Insert Read Log
            do {
                readLogId = try await client.insertReadLog(articleId: articleId)
            } catch {
                print("Failed to insert read log: \(error)")
            }
            
            Task {
                if let timeline = try? await client.fetchIntensityTimeline(workId: articleId) {
                    await MainActor.run {
                        self.intensityTimeline = timeline
                    }
                }
            }
        } catch {
            self.error = error
        }
        isLoading = false
    }
    
    private var customTopBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
            }
            Spacer()
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, UIApplication.shared.keyWindow?.safeAreaInsets.top ?? 44)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
    
    private func updateProgress() {
        guard let id = readLogId else { return }
        
        progressSyncTask?.cancel()
        let pageToSync = currentPage
        
        progressSyncTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try Task.checkCancellation()
                
                try await client.updateReadLog(logId: id, lastPage: pageToSync)
            } catch is CancellationError {
                // Expected when scrolling quickly
            } catch {
                print("Failed to update read log: \(error)")
            }
        }
    }
}

// Swift UI 14+ modifier for color invert
extension View {
    @ViewBuilder
    func extensionColorInvert(_ active: Bool) -> some View {
        if active {
            self.colorInvert()
        } else {
            self
        }
    }
}

struct IntensityGraphView: View {
    let timeline: VioletClient.IntensityTimeline
    let totalPages: Int
    let isScrubbing: Bool
    
    var body: some View {
        Canvas { context, size in
            guard !timeline.peaks.isEmpty, totalPages > 1 else { return }
            
            var path = Path()
            let width = size.width
            let height = size.height
            
            let maxScore = timeline.peaks.map { $0[1] }.max() ?? 1.0
            let normalizedMax = maxScore > 0 ? maxScore : 1.0
            
            var points: [CGPoint] = []
            points.append(CGPoint(x: 0, y: height))
            
            for peak in timeline.peaks {
                let page = peak[0]
                let score = peak[1]
                let x = (page / Double(totalPages - 1)) * width
                let y = height - ((score / normalizedMax) * height * 0.9) // leave a 10% gap at the top
                points.append(CGPoint(x: x, y: y))
            }
            
            points.append(CGPoint(x: width, y: height))
            path.addLines(points)
            path.closeSubpath()
            
            let gradient = Gradient(colors: [
                Color.accentColor.opacity(isScrubbing ? 0.8 : 0.4),
                Color.accentColor.opacity(0.0)
            ])
            context.fill(path, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height)))
        }
        .frame(height: isScrubbing ? 40 : 20)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isScrubbing)
        .allowsHitTesting(false)
    }
}

// Restore native swipe-to-go-back gesture when navigation bar is hidden
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}
