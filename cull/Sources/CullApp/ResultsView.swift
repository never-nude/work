import CullCore
import SwiftUI

struct Checkbox: View {
    let state: CheckState
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Palette rendering: a white tick on a solid terracotta square, or a quiet outline when off.
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(state == .off ? Color.secondary.opacity(0.55) : Color.white, Theme.accent)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
    }

    private var symbol: String {
        switch state {
        case .on: return "checkmark.square.fill"
        case .mixed: return "minus.square.fill"
        case .off: return "square"
        }
    }

    private var accessibilityValue: String {
        switch state {
        case .on: return "selected"
        case .mixed: return "partly selected"
        case .off: return "not selected"
        }
    }
}

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    let report: ScanReport

    var body: some View {
        if report.categories.isEmpty, model.lastSummary == nil {
            MessageView(
                symbol: "checkmark.seal",
                title: "Nothing worth culling",
                detail: "No caches, stale builds or leftovers big enough to bother with."
            )
        } else {
            ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if let summary = model.lastSummary {
                        SummaryBanner(summary: summary)
                            .padding(.horizontal, Theme.rowInset)
                            .padding(.top, 14)
                            .padding(.bottom, 6)
                    }
                    if !report.hasFullDiskAccess {
                        FullDiskAccessHint()
                    }
                    HeadroomHint()
                    ForEach(Tier.allCases, id: \.self) { tier in
                        let categories = report.categories(in: tier)
                        if !categories.isEmpty {
                            Section {
                                ForEach(categories) { category in
                                    CategoryRow(category: category)
                                    if model.expanded.contains(category.id) {
                                        ForEach(category.items) { item in
                                            ItemRow(item: item, showsApp: Self.appCategories.contains(category.id))
                                        }
                                    }
                                    Divider()
                                        .padding(.leading, Theme.rowInset + 34)
                                }
                            } header: {
                                TierHeader(tier: tier, total: categories.reduce(0) { $0 + $1.totalBytes })
                            }
                            .id(tier.rawValue)
                        }
                    }
                    if !report.advisories.isEmpty {
                        AdvisoryList(advisories: report.advisories)
                    }
                    FooterNotes(report: report)
                        .id("footer")
                }
            }
            .task {
                // Snapshots can ask to start further down the list.
                guard let target = Snapshot.scrollTarget else { return }
                try? await Task.sleep(for: .milliseconds(400))
                scroller.scrollTo(target, anchor: .top)
            }
            }
        }
    }

    /// Categories whose item titles are app names or bundle identifiers.
    private static let appCategories: Set<String> = ["caches.apps", "caches.chromium", "caches.containers"]
}

private struct TierHeader: View {
    let tier: Tier
    let total: Int64

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Theme.color(for: tier))
                .frame(width: 8, height: 8)
            Text(tier.title)
                .font(.headline)
            Text(tier.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(Format.bytes(total))
                .font(.headline)
                .monospacedDigit()
        }
        .padding(.horizontal, Theme.rowInset)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct CategoryRow: View {
    @Environment(AppModel.self) private var model
    let category: CullCategory
    @State private var hovering = false

    var body: some View {
        let isExpanded = model.expanded.contains(category.id)
        HStack(spacing: 12) {
            Checkbox(state: model.state(of: category), label: category.title) {
                model.toggle(category)
            }
            .disabled(category.items.isEmpty)
            .opacity(category.items.isEmpty ? 0.3 : 1)

            Image(systemName: category.symbol)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .font(.body.weight(.medium))
                Text(category.note ?? category.blurb)
                    .font(.callout)
                    .foregroundStyle(category.note == nil ? Color.secondary : Color.orange)
                    .lineLimit(isExpanded ? 3 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)

            if category.items.count > 1 {
                Text(countLabel)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Text(Format.bytes(category.totalBytes))
                .font(.body.weight(.medium))
                .monospacedDigit()
                .frame(minWidth: 78, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .opacity(category.items.isEmpty ? 0 : 1)
                .frame(width: 10)
        }
        .padding(.horizontal, Theme.rowInset)
        .padding(.vertical, 9)
        .background(hovering ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !category.items.isEmpty else { return }
            withAnimation(.snappy(duration: 0.18)) { model.toggleExpanded(category) }
        }
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityHint(isExpanded ? "Collapse" : "Expand")
    }
}

extension CategoryRow {
    /// "6 items", or "4 of 6 selected" when the category is only partly ticked.
    fileprivate var countLabel: String {
        let total = category.items.count
        guard model.state(of: category) == .mixed else { return "\(total) items" }
        let selected = category.items.filter { model.selection.contains($0.id) }.count
        return "\(selected) of \(total) selected"
    }
}

private struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: CullItem
    let showsApp: Bool
    @State private var hovering = false

    var body: some View {
        let app = showsApp ? AppIdentity.shared.info(for: item.title) : nil
        HStack(spacing: 10) {
            Checkbox(state: model.selection.contains(item.id) ? .on : .off, label: item.title) {
                model.toggle(item)
            }
            if let icon = app?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(app?.name ?? item.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let caution = item.caution {
                        Label(caution, systemImage: "exclamationmark.triangle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                    }
                    if let detail {
                        Text(detail)
                            .foregroundStyle(.secondary)
                            .truncationMode(.middle)
                    }
                }
                .font(.callout)
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(Format.bytes(item.bytes))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 78, alignment: .trailing)
            Color.clear
                .frame(width: 10, height: 1)
        }
        .padding(.leading, Theme.rowInset + 34)
        .padding(.trailing, Theme.rowInset)
        .padding(.vertical, 6)
        .background(hovering ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(item) }
        .onHover { hovering = $0 }
        .contextMenu {
            if !item.paths.isEmpty {
                Button("Show in Finder") { model.reveal(item) }
                Button("Copy Path") { model.copyPath(item) }
                Divider()
            }
            Button("Never Cull This") { model.neverCull(item) }
        }
    }

    /// When it was last used, and where it lives.
    private var detail: String? {
        var parts: [String] = []
        if let used = Format.lastUsed(item, now: model.now) { parts.append(used) }
        if let subtitle = item.subtitle { parts.append(subtitle) }
        if item.incomplete { parts.append("partly unreadable") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: Banners

private struct SummaryBanner: View {
    @Environment(AppModel.self) private var model
    let summary: CullSummary
    @State private var showingProblems = false

    var body: some View {
        let clean = summary.problems.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: clean ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(clean ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if summary.trashedBytes > 0 {
                    Button("Open Trash") { model.openTrash() }
                }
                Button {
                    model.dismissSummary()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
            }
            if !clean {
                DisclosureGroup(
                    "\(Format.count(summary.problems.count, "item")) could not be fully removed",
                    isExpanded: $showingProblems
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(summary.problems) { outcome in
                            Text("\(outcome.title): \(outcome.message ?? "failed")")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .font(.callout)
            }
        }
        .padding(14)
        .background(
            (clean ? Color.green : Color.orange).opacity(0.10),
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        )
    }

    private var headline: String {
        var text = "Culled \(Format.bytes(summary.deletedBytes))"
        if summary.trashedBytes > 0 {
            text += " and moved \(Format.bytes(summary.trashedBytes)) to the Trash"
        }
        return text
    }

    private var detail: String {
        var sentences: [String] = []
        if let before = summary.diskBefore, let now = model.disk ?? summary.diskAfter {
            sentences.append("\(Format.bytes(now.available)) available now, up from \(Format.bytes(before.available)).")
        }
        if summary.trashedBytes > 0 {
            sentences.append("Empty the Trash to get the rest back.")
        }
        return sentences.joined(separator: " ")
    }
}

private struct FullDiskAccessHint: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.Key.hideFullDiskAccessHint) private var hidden = false

    var body: some View {
        if !hidden {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Disk Access finds more")
                        .font(.headline)
                    Text("macOS keeps the Trash, device backups and sandboxed app caches behind it. Switch Cull on in the list, then reopen it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Open Settings…") { model.openFullDiskAccessSettings() }
                Button {
                    hidden = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Don't show this again")
            }
            .padding(14)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .padding(.horizontal, Theme.rowInset)
            .padding(.top, 14)
            .padding(.bottom, 6)
        }
    }
}

/// Shown when the disk would still be short of room after culling everything selected:
/// points at the biggest things that are on offer but not ticked.
private struct HeadroomHint: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let suggestions = model.biggestUnselected
        if let pressure = model.pressureAfterCull, pressure != .comfortable, !suggestions.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Theme.color(for: pressure))
                VStack(alignment: .leading, spacing: 3) {
                    Text(pressure == .critical
                        ? "Still critically low after this cull"
                        : "Still tight after this cull")
                        .font(.headline)
                    Text("The biggest things not selected: " + suggestions.map {
                        "\($0.category) › \($0.item.title) (\(Format.bytes($0.item.bytes)))"
                    }.joined(separator: "; ") + ".")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                Theme.color(for: pressure).opacity(0.09),
                in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
            )
            .padding(.horizontal, Theme.rowInset)
            .padding(.top, 14)
            .padding(.bottom, 6)
        }
    }
}

// MARK: Advisories and footer

private struct AdvisoryList: View {
    let advisories: [Advisory]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                Text("Also large")
                    .font(.headline)
                Text("Cull leaves these alone")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Theme.rowInset)
            .padding(.vertical, 8)
            Divider()
            ForEach(advisories) { advisory in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(advisory.title)
                            .font(.body.weight(.medium))
                        Text(advisory.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    if let hint = advisory.hint {
                        Text(hint)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    Text(Format.bytes(advisory.bytes))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                        .frame(minWidth: 78, alignment: .trailing)
                }
                .padding(.leading, Theme.rowInset + 34)
                .padding(.trailing, Theme.rowInset + 22)
                .padding(.vertical, 9)
                Divider()
                    .padding(.leading, Theme.rowInset + 34)
            }
        }
    }
}

private struct FooterNotes: View {
    @Environment(AppModel.self) private var model
    let report: ScanReport

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let environment = model.environment, environment.isSandbox {
                Label("Sandbox home: \(environment.home)", systemImage: "shippingbox")
            }
            ForEach(report.notes.filter { !$0.contains("Full Disk Access") }, id: \.self) { note in
                Text(note)
            }
            Text("Scanned in \(String(format: "%.1f", report.finishedAt.timeIntervalSince(report.startedAt))) seconds. Right-click anything to show it in Finder or to stop Cull offering it.")
        }
        .font(.callout)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, Theme.rowInset)
        .padding(.vertical, 16)
    }
}
