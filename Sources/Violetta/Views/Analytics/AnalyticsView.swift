import SwiftUI
import Charts

struct AnalyticsView: View {
    @Environment(VioletClient.self) private var client
    @AppStorage("themeColor") private var themeColor = "purple"
    @State private var activity: VioletClient.UserActivity?
    @State private var isLoading = false
    @State private var error: Error?
    @State private var navigationWork: Article? = nil
    
    enum TimeScale: String, CaseIterable, Identifiable {
        case days10 = "10d"
        case month = "1mo"
        case year = "1y"
        case all = "All"
        
        var id: String { rawValue }
        var label: String { rawValue }
    }
    @State private var timeScale: TimeScale = .days10
    
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView().frame(maxHeight: .infinity)
                } else if let error = error {
                    ErrorStateView(error: error) {
                        Task { await loadData() }
                    }
                } else {
                    activityContent
                }
            }
            .navigationTitle("Analytics")
            .navigationDestination(item: $navigationWork) { article in
                ArticleView(article: article)
            }
            .task {
                if activity == nil {
                    await loadData()
                }
            }
        }
    }
    
    @ViewBuilder
    private var activityContent: some View {
        if let activity = activity {
            ScrollView {
                VStack(spacing: 24) {
                    HStack {
                        statBox(title: "Reads", value: activity.totals.reads, icon: "book.fill")
                        statBox(title: "Bookmarks", value: activity.totals.bookmarks, icon: "bookmark.fill")
                        statBox(title: "Downloads", value: activity.totals.downloads, icon: "arrow.down.circle.fill")
                    }
                    .padding(.horizontal)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Activity Trend")
                            .font(.title2.bold())
                            .padding(.horizontal)
                        
                        Picker("Time Scale", selection: $timeScale) {
                            ForEach(TimeScale.allCases) { scale in
                                Text(scale.label).tag(scale)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        
                        Chart {
                            ForEach(filteredDays) { day in
                                LineMark(
                                    x: .value("Date", day.date),
                                    y: .value("Reads", day.reads)
                                )
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 3))
                                .foregroundStyle(Color.accentColor)
                                
                                PointMark(
                                    x: .value("Date", day.date),
                                    y: .value("Reads", day.reads)
                                )
                                .foregroundStyle(Color.accentColor)
                                
                                AreaMark(
                                    x: .value("Date", day.date),
                                    y: .value("Reads", day.reads)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(0.4),
                                            Color.accentColor.opacity(0.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            }
                        }
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                                AxisGridLine()
                                AxisValueLabel()
                            }
                        }
                        .frame(height: 250)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .refreshable {
                await loadData()
            }
        } else {
            ContentUnavailableView("No Activity", systemImage: "chart.xyaxis.line", description: Text("Read articles to see your analytics."))
        }
    }
    
    private func statBox(title: String, value: Int, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .scaleEffect(x: icon.contains("bookmark") ? 1.35 : 1.0, y: icon.contains("bookmark") ? 0.95 : 1.0)
                .foregroundStyle(Color.accentColor)
            Text("\(value)")
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private func loadData() async {
        isLoading = true
        error = nil
        do {
            activity = try await client.fetchActivity()
        } catch {
            self.error = error
        }
        isLoading = false
    }
    
    private var filteredDays: [VioletClient.ActivityDay] {
        guard let days = activity?.days else { return [] }
        if timeScale == .all { return days }
        
        let now = Date()
        let daysToKeep: Int
        switch timeScale {
        case .days10: daysToKeep = 10
        case .month: daysToKeep = 30
        case .year: daysToKeep = 365
        case .all: daysToKeep = Int.max
        }
        
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysToKeep, to: now) ?? now
        
        let isoFormatter = ISO8601DateFormatter()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        return days.filter { day in
            let parsedDate = isoFormatter.date(from: day.date) ?? dateFormatter.date(from: day.date)
            guard let d = parsedDate else { return true }
            return d >= cutoff
        }
    }
}
