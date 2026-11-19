import EventKit
import Foundation
import Observation
import StickyCore
import os

/// One-way import Reminders → StickyDesk. Never writes back to Reminders.
@MainActor
@Observable
final class RemindersImportController {
    enum Access: Equatable {
        case notDetermined, granted, denied, restricted, writeOnly
    }

    private(set) var access: Access = .notDetermined
    private(set) var lists: [ReminderList] = []
    private(set) var isImporting = false
    private(set) var lastSummary: MergeSummary?
    private(set) var lastImportDate: Date?

    var selectedListIDs: Set<String> {
        didSet { defaults.set(Array(selectedListIDs), forKey: Keys.selectedLists) }
    }

    var removeOrphans: Bool {
        didSet { defaults.set(removeOrphans, forKey: Keys.removeOrphans) }
    }

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private let gateway = RemindersGateway()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observeTask: Task<Void, Never>?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "com.jfzepeda.stickydesk", category: "reminders")

    private enum Keys {
        static let selectedLists = "reminders.selectedListIDs"
        static let removeOrphans = "reminders.removeOrphans"
    }

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        // Default: no list selected.
        self.selectedListIDs = Set(defaults.stringArray(forKey: Keys.selectedLists) ?? [])
        self.removeOrphans = defaults.bool(forKey: Keys.removeOrphans)
        refreshAccess()
    }

    /// Called at launch: refresh lists if already authorized and start observing changes.
    func start() {
        refreshAccess()
        guard access == .granted else { return }
        lists = gateway.lists()
        startObserving()
    }

    func requestAccess() async {
        do {
            _ = try await gateway.requestAccess()
        } catch {
            logger.error("Reminders access request failed: \(error.localizedDescription, privacy: .public)")
        }
        refreshAccess()
        if access == .granted {
            lists = gateway.lists()
            startObserving()
        }
    }

    func toggle(_ list: ReminderList) {
        if selectedListIDs.contains(list.id) {
            selectedListIDs.remove(list.id)
        } else {
            selectedListIDs.insert(list.id)
        }
    }

    func importNow() async {
        guard access == .granted, !selectedListIDs.isEmpty, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        // Drop selections for lists that no longer exist.
        lists = gateway.lists()
        let valid = selectedListIDs.intersection(lists.map(\.id))
        if valid != selectedListIDs { selectedListIDs = valid }
        guard !valid.isEmpty else { return }

        let reminders = await gateway.incompleteReminders(inListsWithIDs: valid)
        let removeOrphans = removeOrphans
        let summary = await model.perform { store in
            ReminderMerger.merge(reminders, into: &store, removeOrphans: removeOrphans)
        }
        if let summary {
            lastSummary = summary
            lastImportDate = Date()
        }
    }

    // MARK: Private

    private func refreshAccess() {
        access = switch RemindersGateway.authorizationStatus {
        case .fullAccess: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .writeOnly: .writeOnly
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    /// Re-import the selected lists whenever Reminders changes (debounced), while the app runs.
    private func startObserving() {
        guard observeTask == nil else { return }
        let changes = gateway.changes
        observeTask = Task { [weak self] in
            for await _ in changes {
                self?.scheduleReimport()
            }
        }
    }

    private func scheduleReimport() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            self.lists = self.gateway.lists()
            await self.importNow()
        }
    }
}
