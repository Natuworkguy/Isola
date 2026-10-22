import AppKit
import EventKit
import SwiftUI

struct CalendarEntry: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
}

final class CalendarMonitor: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var entries: [CalendarEntry] = []
    @Published private(set) var access: Access = .unknown

    private let store = EKEventStore()
    private var timer: Timer?
    private var observing = false

    func activate() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            begin()
        case .notDetermined:
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.access = granted ? .granted : .denied
                    if granted { self?.begin() }
                }
            }
        default:
            access = .denied
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    private func begin() {
        refresh()
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in self?.refresh() }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        let now = Date()
        let horizon = Calendar.current.date(byAdding: .day, value: 3, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: horizon, calendars: nil)
        let upcoming = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
        entries = upcoming.map { event in
            CalendarEntry(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Untitled",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                color: Color(nsColor: event.calendar.color)
            )
        }
    }
}
