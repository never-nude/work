import AppKit
import CullCore
import Observation
import SwiftUI

enum CheckState {
    case on, off, mixed
}

/// Everything the window shows, and the three things it can do: scan, select, cull.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case starting
        case scanning
        case ready
        case culling
        case failed(String)
    }

    private(set) var phase: Phase = .starting
    private(set) var report: ScanReport?
    private(set) var environment: CullEnvironment?
    private(set) var disk: DiskSpace?
    private(set) var volumeName = "Macintosh HD"
    private(set) var scanProgress: ScanProgress?
    private(set) var cullProgress: CullProgress?
    private(set) var lastSummary: CullSummary?

    var selection: Set<String> = []
    var expanded: Set<String> = []
    var showingConfirmation = false

    @ObservationIgnored private var scanTask: Task<ScanReport, Never>?
    @ObservationIgnored private var scanGeneration = 0
    @ObservationIgnored private var snapshotDidCull = false

    // MARK: Derived

    var isBusy: Bool { phase == .scanning || phase == .culling || phase == .starting }

    var selectedItems: [CullItem] {
        report?.allItems.filter { selection.contains($0.id) } ?? []
    }

    var selectedBytes: Int64 { report?.bytes(selected: selection) ?? 0 }

    /// Bytes that come back immediately: everything selected that is not merely moved to the Trash.
    var selectedBytesFreedNow: Int64 {
        selectedItems.reduce(0) { $0 + ($1.action == .trash ? 0 : $1.bytes) }
    }

    var canCull: Bool { phase == .ready && !selection.isEmpty }

    /// How full the disk will still be once the current selection is gone.
    var pressureAfterCull: DiskSpace.Pressure? {
        guard let disk else { return nil }
        return DiskSpace(total: disk.total, free: disk.available + selectedBytesFreedNow).pressure
    }

    /// The largest things on offer that are not selected, for when the selection is not enough.
    var biggestUnselected: [(item: CullItem, category: String)] {
        guard let report else { return [] }
        let candidates = report.categories.flatMap { category in
            category.items
                .filter { !selection.contains($0.id) && $0.bytes >= 500_000_000 }
                .map { (item: $0, category: category.title) }
        }
        return Array(candidates.sorted { $0.item.bytes > $1.item.bytes }.prefix(3))
    }

    var now: Date { environment?.now ?? Date() }

    func state(of category: CullCategory) -> CheckState {
        let selected = category.items.filter { selection.contains($0.id) }.count
        if selected == 0 { return .off }
        return selected == category.items.count ? .on : .mixed
    }

    func selectedBytes(in category: CullCategory) -> Int64 {
        category.items.reduce(0) { $0 + (selection.contains($1.id) ? $1.bytes : 0) }
    }

    // MARK: Scan

    func start() {
        guard phase == .starting else { return }
        scan()
    }

    func scan() {
        guard phase != .culling else { return }
        scanTask?.cancel()

        if CullEnvironment.isRunningAsRoot {
            phase = .failed("Cull is running as root. Quit and open it normally: it only ever touches your own files.")
            return
        }
        let environment: CullEnvironment
        do {
            environment = try CullEnvironment.live()
        } catch {
            phase = .failed("\(error)")
            return
        }
        self.environment = environment
        disk = currentDisk(in: environment)
        volumeName = DiskSpace.volumeName(of: environment.home) ?? "Disk"
        scanProgress = nil
        phase = .scanning

        scanGeneration += 1
        let generation = scanGeneration
        let options = AppSettings.scanOptions
        // The model lives as long as the app does, so the background work can hold on to it.
        let task = Task.detached(priority: .userInitiated) {
            await Scanner(environment: environment, options: options).scan { progress in
                Task { @MainActor in self.receive(progress, generation: generation) }
            }
        }
        scanTask = task
        Task {
            let report = await task.value
            finishScan(report, generation: generation)
        }
    }

    private func currentDisk(in environment: CullEnvironment) -> DiskSpace? {
        if environment.isSandbox, let pretend = Snapshot.pretendDisk { return pretend }
        return DiskSpace.of(path: environment.home)
    }

    private func receive(_ progress: ScanProgress, generation: Int) {
        guard generation == scanGeneration, phase == .scanning else { return }
        // Results arrive out of order across threads; never let the bar move backwards.
        if let current = scanProgress, current.phase == progress.phase, current.completed > progress.completed { return }
        scanProgress = progress
    }

    private func finishScan(_ report: ScanReport, generation: Int) {
        guard generation == scanGeneration, !report.cancelled else { return }
        self.report = report
        if let environment { disk = currentDisk(in: environment) ?? report.disk }
        selection = report.defaultSelection
        // Open what has a decision in it: anything only partly selected.
        expanded = Set(report.categories.filter { state(of: $0) == .mixed }.map(\.id))
        scanProgress = nil
        phase = .ready

        if Snapshot.path != nil {
            // A snapshot of the "after" state: cull once, then photograph the rescan. Sandbox homes only.
            if Snapshot.cullsFirst, environment?.isSandbox == true, !snapshotDidCull {
                snapshotDidCull = true
                cull()
                return
            }
            if Snapshot.expandsEverything { expandAll() }
            Snapshot.captureAndQuit()
        }
    }

    // MARK: Select

    func toggle(_ item: CullItem) {
        if selection.contains(item.id) {
            selection.remove(item.id)
        } else {
            selection.insert(item.id)
        }
    }

    func toggle(_ category: CullCategory) {
        let identifiers = category.items.map(\.id)
        if state(of: category) == .on {
            selection.subtract(identifiers)
        } else {
            selection.formUnion(identifiers)
        }
    }

    func toggleExpanded(_ category: CullCategory) {
        if expanded.contains(category.id) {
            expanded.remove(category.id)
        } else {
            expanded.insert(category.id)
        }
    }

    func selectRecommended() {
        selection = report?.defaultSelection ?? []
    }

    func selectNothing() {
        selection = []
    }

    func expandAll() {
        expanded = Set(report?.categories.map(\.id) ?? [])
    }

    func collapseAll() {
        expanded = []
    }

    /// Stops offering an item, now and in future scans.
    func neverCull(_ item: CullItem) {
        // One folder is remembered by its path, which survives renames of the rule that found it.
        // Anything made of several places (or of none, like a simulator) is remembered by its id.
        AppSettings.addExclusions(item.paths.count == 1 ? item.paths : [item.id])
        selection.remove(item.id)
        guard var report else { return }
        for index in report.categories.indices {
            report.categories[index].items.removeAll { $0.id == item.id }
        }
        report.categories.removeAll { $0.items.isEmpty && $0.note == nil }
        self.report = report
    }

    // MARK: Cull

    var confirmationTitle: String {
        "Cull \(Format.bytes(selectedBytes))?"
    }

    var confirmationMessage: String {
        let items = selectedItems
        let trashed = items.filter { $0.action == .trash }
        let deleted = items.filter { $0.action != .trash }
        var sentences: [String] = []
        if !deleted.isEmpty {
            let bytes = deleted.reduce(0) { $0 + $1.bytes }
            sentences.append("\(Format.count(deleted.count, "item")) (\(Format.bytes(bytes))) will be deleted for good.")
        }
        if !trashed.isEmpty {
            let bytes = trashed.reduce(0) { $0 + $1.bytes }
            sentences.append("\(Format.count(trashed.count, "item")) (\(Format.bytes(bytes))) will move to the Trash.")
        }
        return sentences.joined(separator: " ")
    }

    /// The Cull button: asks first unless the user turned that off.
    func requestCull() {
        guard canCull else { return }
        if AppSettings.confirmBeforeCulling {
            showingConfirmation = true
        } else {
            cull()
        }
    }

    func cull() {
        guard canCull, let environment else { return }
        let items = selectedItems
        phase = .culling
        cullProgress = CullProgress(completed: 0, total: items.count, current: "", bytesSoFar: 0)
        lastSummary = nil

        Task {
            let summary = await Task.detached(priority: .userInitiated) {
                await Culler(environment: environment).cull(items) { progress in
                    Task { @MainActor in self.receive(progress) }
                }
            }.value
            cullProgress = nil
            lastSummary = summary
            phase = .ready
            scan()
        }
    }

    private func receive(_ progress: CullProgress) {
        guard phase == .culling else { return }
        if let current = cullProgress, current.completed > progress.completed { return }
        cullProgress = progress
    }

    func dismissSummary() {
        lastSummary = nil
    }

    // MARK: Finder and System Settings

    func reveal(_ item: CullItem) {
        let urls = item.paths.prefix(20).map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyPath(_ item: CullItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.paths.joined(separator: "\n"), forType: .string)
    }

    func openTrash() {
        guard let environment else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: environment.home + "/.Trash"))
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
