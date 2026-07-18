import SwiftUI

enum ReadingDirection: String, CaseIterable, Identifiable {
    case vertical = "Vertical Scroll"
    case leftToRight = "Left to Right"
    case rightToLeft = "Right to Left"
    
    var id: String { self.rawValue }
}

enum ImageScaleType: String, CaseIterable, Identifiable {
    case fit = "Fit Screen"
    case fill = "Fill Screen"
    
    var id: String { self.rawValue }
}

@MainActor
class ReaderSettings: ObservableObject {
    static let shared = ReaderSettings()
    
    @AppStorage("reader_direction") var direction: ReadingDirection = .vertical
    @AppStorage("reader_double_page") var isDoublePaged: Bool = false
    @AppStorage("reader_isolate_first_page") var isolateFirstPage: Bool = true
    @AppStorage("reader_tap_navigate") var tapToNavigate: Bool = true
    @AppStorage("reader_invert_tap") var invertTapToNavigate: Bool = false
    @AppStorage("reader_scale_type") var scaleType: ImageScaleType = .fit
    @AppStorage("reader_page_padding") var pagePadding: Double = 0.0
    @AppStorage("reader_background_color") var useDarkBackground: Bool = true
    @AppStorage("reader_grayscale") var useGrayscale: Bool = false
    @AppStorage("reader_color_invert") var useColorInvert: Bool = false
    @AppStorage("reader_split_wide_pages") var splitWidePages: Bool = false
    @AppStorage("reader_fullscreen_mode") var fullscreenMode: Bool = true
    @AppStorage("reader_render_quality") var renderQuality: Double = 100.0
}
