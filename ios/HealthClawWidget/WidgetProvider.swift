import WidgetKit

struct HealthEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct HealthWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthEntry {
        HealthEntry(date: .now, data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthEntry) -> Void) {
        completion(HealthEntry(date: .now, data: WidgetDataCache.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthEntry>) -> Void) {
        let data = WidgetDataCache.load()
        let entry = HealthEntry(date: .now, data: data)
        // Refresh every 30 min
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: .now)!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
