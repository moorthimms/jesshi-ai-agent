import Foundation
import EventKit
import UserNotifications
import Security
import SwiftUI

struct CalendarBriefingView: View {
    @State private var days = 1
    @State private var entries: [EKEvent] = []
    @State private var message = ""
    @State private var loading = false
    let services: DeviceServices

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Date range", selection: $days) {
                Text("Today").tag(1)
                Text("Next 7 days").tag(7)
            }
            .pickerStyle(.segmented)
            .disabled(loading)
            .onChange(of: days) { _, _ in
                entries = []
                message = ""
            }
            Button("Load calendar briefing", systemImage: "calendar") { load() }
                .disabled(loading)
            if loading { ProgressView("Reading calendar…") }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, event in
                VStack(alignment: .leading) {
                    Text(event.title ?? "Untitled event").font(.headline)
                    Text(event.startDate.formatted(date: .abbreviated, time: event.isAllDay ? .omitted : .shortened))
                    if event.isAllDay { Text("All day").font(.caption) }
                }
            }
        }
    }

    private func load() {
        loading = true
        entries = []
        message = ""
        Task { @MainActor in
            defer { loading = false }
            do {
                entries = try await services.calendarBriefing(days: days)
                if entries.isEmpty { message = "No events in this date range." }
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

final class DeviceServices: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var status = ""
    @Published var homeURL = UserDefaults.standard.string(forKey: "jessy.homeURL") ?? ""
    @Published var homeToken = ""
    private let events = EKEventStore()
    override init() { super.init(); UNUserNotificationCenter.current().delegate = self }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    func report(_ text: String) { DispatchQueue.main.async { self.status = text } }
    func schedule(id: String, title: String, date: Date) {
        guard date > Date() else { report("Choose a future time."); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, error in
            guard allowed else { self.report(error?.localizedDescription ?? "Notifications are not allowed."); return }
            let content = UNMutableNotificationContent(); content.title = "Jessy reminder"; content.body = title; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { error in
                self.report(error?.localizedDescription ?? "Reminder scheduled on this device.")
            }
        }
    }
    func cancel(id: String) { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id]) }
    @MainActor
    func calendarBriefing(days: Int) async throws -> [EKEvent] {
        guard try await events.requestFullAccessToEvents() else {
            throw NSError(domain: "Jessy.Calendar", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Allow full calendar access in Settings to view your briefing."
            ])
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return [] }
        let predicate = events.predicateForEvents(withStart: start, end: end, calendars: nil)
        return events.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
    func addReminder(_ title: String, date: Date?) {
        events.requestFullAccessToReminders { allowed, error in
            guard allowed else { self.report(error?.localizedDescription ?? "Reminders access denied."); return }
            let item = EKReminder(eventStore: self.events); item.title = title
            guard let calendar = self.events.defaultCalendarForNewReminders() else { self.report("No writable reminders list is configured."); return }
            item.calendar = calendar
            if let date { item.dueDateComponents = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: date); item.addAlarm(EKAlarm(absoluteDate: date)) }
            do { try self.events.save(item, commit: true); self.report("Added to Apple Reminders.") }
            catch { self.report(error.localizedDescription) }
        }
    }
    func addEvent(_ title: String, date: Date) {
        events.requestWriteOnlyAccessToEvents { allowed, error in
            guard allowed else { self.report(error?.localizedDescription ?? "Calendar access denied."); return }
            let item = EKEvent(eventStore: self.events); item.title = title; item.startDate = date; item.endDate = date.addingTimeInterval(3600)
            guard let calendar = self.events.defaultCalendarForNewEvents else { self.report("No writable calendar is configured."); return }
            item.calendar = calendar
            do { try self.events.save(item, span: .thisEvent); self.report("Added a one-hour event to Apple Calendar.") }
            catch { self.report(error.localizedDescription) }
        }
    }
    private var tokenQuery: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "local.jessy.home", kSecAttrAccount as String: "token"] }
    func saveHomeSettings() {
        guard Self.localURL(homeURL) != nil else { status = "Use an http(s) address with a private IPv4 address or a .local host."; return }
        if !homeToken.isEmpty {
            var query = tokenQuery; query[kSecValueData as String] = Data(homeToken.utf8)
            SecItemDelete(tokenQuery as CFDictionary)
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { status = "Could not save token to Keychain."; return }
            homeToken = ""
        }
        UserDefaults.standard.set(homeURL, forKey: "jessy.homeURL"); status = "Local Home Assistant settings saved. Token is stored in Keychain."
    }
    static func localURL(_ string: String) -> URL? {
        guard let u = URL(string: string), ["http", "https"].contains(u.scheme?.lowercased() ?? ""),
              u.user == nil, u.password == nil, u.query == nil, u.fragment == nil, let host = u.host?.lowercased() else { return nil }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        let privateIP = octets.count == 4 && octets.allSatisfy { (0...255).contains($0) } &&
            (octets[0] == 10 || octets[0] == 127 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])))
        return privateIP || host.hasSuffix(".local") || host == "localhost" ? u : nil
    }
    func controlLight(entity: String, on: Bool) {
        guard let base = Self.localURL(homeURL), entity.range(of: "^light\\.[a-z0-9_]+$", options: .regularExpression) != nil else { status = "Enter a local server and a light.entity_id."; return }
        var query = tokenQuery; query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else { status = "Save a Home Assistant token first."; return }
        let url = base.appendingPathComponent("api/services/light/" + (on ? "turn_on" : "turn_off"))
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 15
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["entity_id": entity])
        // Refuse redirects so a local service cannot forward the token elsewhere.
        let session = URLSession(configuration: .ephemeral, delegate: NoRedirect(), delegateQueue: nil)
        session.dataTask(with: request) { _, response, error in
            defer { session.finishTasksAndInvalidate() }
            let success = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            self.report(error?.localizedDescription ?? (success ? "Light command accepted by Home Assistant." : "Home Assistant rejected the command."))
        }.resume()
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
