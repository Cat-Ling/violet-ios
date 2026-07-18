import SwiftUI

struct AppShell: View {
    @AppStorage("themeColor") private var themeColor = "purple"
    @AppStorage("themeMode") private var themeMode = "dark"
    @State private var selectedTab = 0
    @EnvironmentObject private var appState: AppStateManager
    
    var tabSelection: Binding<Int> {
        Binding {
            selectedTab
        } set: { newValue in
            if newValue == selectedTab && newValue == 1 {
                AppStateManager.shared.searchTabDoubleTapped.send()
            }
            selectedTab = newValue
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !appState.isOnline {
                Text("No Internet Connection")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.red)
            }
            
            TabView(selection: tabSelection) {
                Tab("Home", systemImage: "house", value: 0) {
                    HomeView()
                }
                
                Tab("Search", systemImage: "magnifyingglass", value: 1) {
                    SearchView()
                }
                
                Tab(value: 2) {
                    LibraryView()
                } label: {
                    Label {
                        Text("Library")
                    } icon: {
                        Image(systemName: "bookmark")
                            .scaleEffect(x: 1.15, y: 0.9)
                    }
                }
                
                Tab("Analytics", systemImage: "chart.xyaxis.line", value: 3) {
                    AnalyticsView()
                }
                
                Tab("Settings", systemImage: "gearshape", value: 4) {
                    SettingsView()
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
            .onChange(of: themeColor) { _, newValue in
                updateTheme(mode: themeMode, color: newValue)
            }
            .onChange(of: themeMode) { _, newValue in
                updateTheme(mode: newValue, color: themeColor)
            }
            .onAppear {
                updateTheme(mode: themeMode, color: themeColor)
            }
        }
    }
    
    private func updateTheme(mode: String, color: String) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        
        window.tintColor = UIColor(Color.themeColor(for: color))
        
        if mode == "light" {
            window.overrideUserInterfaceStyle = .light
        } else if mode == "dark" {
            window.overrideUserInterfaceStyle = .dark
        } else {
            window.overrideUserInterfaceStyle = .unspecified
        }
    }
}
