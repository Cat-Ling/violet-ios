import SwiftUI

struct ReaderSettingsView: View {
    @StateObject private var settings = ReaderSettings.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Mode") {
                    Picker("Reading Direction", selection: $settings.direction) {
                        ForEach(ReadingDirection.allCases) { dir in
                            Text(dir.rawValue).tag(dir)
                        }
                    }
                }
                
                Section("Paging Options") {
                    Toggle("Double Paged", isOn: $settings.isDoublePaged)
                    Toggle("Always Isolate First Page", isOn: $settings.isolateFirstPage)
                        .disabled(!settings.isDoublePaged)
                }
                .disabled(settings.direction == .vertical)
                
                Section("Navigation") {
                    Toggle("Tap Sides To Navigate", isOn: $settings.tapToNavigate)
                        .disabled(settings.direction == .vertical)
                    Toggle("Invert Navigation Regions", isOn: $settings.invertTapToNavigate)
                        .disabled(!settings.tapToNavigate || settings.direction == .vertical)
                    Toggle("Fullscreen", isOn: $settings.fullscreenMode)
                }
                
                Section("Vertical Options") {
                    VStack(alignment: .leading) {
                        Text("Page Padding")
                        Slider(value: $settings.pagePadding, in: 0...50, step: 5)
                    }
                }
                .disabled(settings.direction != .vertical)
                
                Section("Image Options") {
                    Picker("Scale Type", selection: $settings.scaleType) {
                        ForEach(ImageScaleType.allCases) { scale in
                            Text(scale.rawValue).tag(scale)
                        }
                    }
                    Toggle("Split Wide Pages", isOn: $settings.splitWidePages)
                        .disabled(settings.direction == .vertical)
                }
                
                Section("Background") {
                    Toggle("Use Dark Background", isOn: $settings.useDarkBackground)
                }
                
                Section("Performance & Quality") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Rendering Quality")
                            Spacer()
                            Text(settings.renderQuality >= 200.0 ? "Original" : "\(Int(settings.renderQuality))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.renderQuality, in: 50...200, step: 10)
                    }
                }
                
                Section("Filters") {
                    Toggle("Grayscale", isOn: $settings.useGrayscale)
                    Toggle("Color Invert", isOn: $settings.useColorInvert)
                }
            }
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
