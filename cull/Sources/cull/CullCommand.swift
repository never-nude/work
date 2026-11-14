import CullCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// `cull`: the same engine as the app, for the terminal.
/// Scans by default and deletes nothing until asked with `--apply`.
@main
struct CullCommand {
    static func main() async {
        let options: Options
        do {
            options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
        } catch let error as UsageError {
            printError("cull: \(error.message)\nTry `cull --help`.")
            exit(2)
        } catch {
            printError("cull: \(error)")
            exit(2)
        }

        if options.help {
            print(Options.usage)
            return
        }
        if options.version {
            print("cull \(CullInfo.version)")
            return
        }
        if options.list {
            printCatalog()
            return
        }
        exit(await run(options))
    }

    // MARK: Run

    static func run(_ options: Options) async -> Int32 {
        let environment: CullEnvironment
        do {
            environment = try CullEnvironment.live(overrideHome: options.home)
        } catch {
            printError("cull: \(error)")
            return 1
        }
        if CullEnvironment.isRunningAsRoot {
            printError("cull: don't run this with sudo. Cull only touches your own files and refuses to delete as root.")
            return 1
        }

        var scanOptions = ScanOptions()
        if let days = options.staleDays { scanOptions.staleDays = days }
        if let days = options.projectDays { scanOptions.projectStaleDays = days }
        if let days = options.downloadDays { scanOptions.downloadsAgeDays = days }
        scanOptions.projectRoots = options.roots
        scanOptions.onlyCategories = options.only
        scanOptions.exclusions = options.never.map { path in
            if path == "~" { return environment.home }
            return path.hasPrefix("~/") ? environment.home + path.dropFirst(1) : path
        }

        let terminal = Terminal(color: options.color)
        let showProgress = !options.json && terminal.errorIsInteractive
        let report = await Scanner(environment: environment, options: scanOptions).scan { progress in
            guard showProgress, progress.phase == .measuring else { return }
            Terminal.status("Weighing \(progress.completed) of \(progress.total)  \(progress.current)")
        }
        if showProgress { Terminal.clearStatus() }

        let selection = options.selection(for: report)
        let selected = report.allItems.filter { selection.contains($0.id) }

        guard options.apply else {
            if options.json {
                printJSON(Output(report: report, selected: selection.sorted(), summary: nil))
            } else {
                Printer(terminal: terminal, environment: environment, verbose: options.verbose)
                    .printReport(report, selection: selection, applied: false)
            }
            return 0
        }

        if !options.json {
            Printer(terminal: terminal, environment: environment, verbose: options.verbose)
                .printReport(report, selection: selection, applied: true)
        }
        guard !selected.isEmpty else {
            if options.json { printJSON(Output(report: report, selected: [], summary: nil)) }
            return 0
        }

        if !options.yes {
            guard terminal.inputIsInteractive else {
                printError("cull: refusing to delete without confirmation. Add --yes to run unattended.")
                return 2
            }
            let trashed = selected.filter { $0.action == .trash }.count
            var question = "Cull \(Format.bytes(report.bytes(selected: selection)))?"
            question += trashed > 0
                ? " \(Format.count(trashed, "item")) go to the Trash; the rest is deleted for good."
                : " This deletes for good."
            print("\(question) [y/N] ", terminator: "")
            fflush(stdout)
            let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
            guard answer == "y" || answer == "yes" else {
                print("Nothing was deleted.")
                return 0
            }
        }

        let summary = await Culler(environment: environment).cull(selected) { progress in
            guard showProgress, !progress.current.isEmpty else { return }
            Terminal.status("Culling \(progress.completed + 1) of \(progress.total)  \(progress.current)")
        }
        if showProgress { Terminal.clearStatus() }

        if options.json {
            printJSON(Output(report: report, selected: selection.sorted(), summary: summary))
        } else {
            Printer(terminal: terminal, environment: environment, verbose: options.verbose).printSummary(summary)
        }
        return summary.problems.isEmpty ? 0 : 1
    }

    // MARK: Output

    struct Output: Encodable {
        let report: ScanReport
        let selected: [String]
        let summary: CullSummary?
    }

    static func printJSON(_ output: Output) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(output) else {
            printError("cull: could not encode the report")
            return
        }
        print(String(decoding: data, as: UTF8.self))
    }

    static func printCatalog() {
        for tier in Tier.allCases {
            print("\(tier.title.uppercased())  \(tier.explanation)")
            for entry in CullCatalog.entries where entry.tier == tier {
                print("  \(entry.id.padding(toLength: 22, withPad: " ", startingAt: 0))  \(entry.title)")
            }
            print("")
        }
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

struct UsageError: Error {
    let message: String
}

struct Options {
    var apply = false
    var yes = false
    var json = false
    var verbose = false
    var list = false
    var help = false
    var version = false
    var color: Bool?
    var only: Set<String>?
    var include: Set<String> = []
    var exclude: Set<String> = []
    var never: [String] = []
    var roots: [String]?
    var staleDays: Int?
    var projectDays: Int?
    var downloadDays: Int?
    var home: String?

    static let usage = """
    cull \(CullInfo.version) — find and remove what your Mac does not need to keep

    USAGE
      cull                     Scan and show what would be culled. Deletes nothing.
      cull --apply             Cull everything that is pre-selected, after asking.
      cull --apply --yes       Same, without asking (for scripts and shortcuts).

    WHAT GETS SELECTED
      Safe items are pre-selected. Rebuildable items are pre-selected once stale.
      Personal files ("Your call") are never pre-selected and go to the Trash.
      --include <ids>          Also select everything in these categories.
                               `rebuildable` selects that whole tier.
      --exclude <ids>          Deselect these categories.
      --only <ids>             Scan only these categories.
      --never <paths>          Never offer these paths or anything inside them.

    TUNING
      --stale-days <n>         Xcode build data counts as stale after n days (default 14).
      --project-days <n>       A project counts as idle after n days (default 30).
      --download-days <n>      Downloads count as old after n days (default 90).
      --roots <paths>          Folders to search for projects (default: the usual places).

    OUTPUT
      -v, --verbose            List every item instead of the largest few.
      --json                   Print the report (and the result of --apply) as JSON.
      --list                   List category ids.
      --no-color               Plain output.
      -h, --help               Show this help.
      --version                Show the version.

    Lists are comma-separated. Paths may start with ~.
    Set \(CullEnvironment.homeOverrideVariable) (or pass --home) to try Cull on a stand-in home folder.
    """

    static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0

        func value(for flag: String) throws -> String {
            index += 1
            guard index < arguments.count else { throw UsageError(message: "\(flag) needs a value") }
            return arguments[index]
        }
        func list(for flag: String) throws -> [String] {
            try value(for: flag).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        func days(for flag: String) throws -> Int {
            let raw = try value(for: flag)
            guard let number = Int(raw), number >= 0 else {
                throw UsageError(message: "\(flag) needs a whole number of days, not \"\(raw)\"")
            }
            return number
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--apply": options.apply = true
            case "--yes", "-y": options.yes = true
            case "--json": options.json = true
            case "--verbose", "-v": options.verbose = true
            case "--list": options.list = true
            case "--help", "-h": options.help = true
            case "--version": options.version = true
            case "--no-color": options.color = false
            case "--color": options.color = true
            case "--only": options.only = Set(try list(for: argument))
            case "--include": options.include.formUnion(try list(for: argument))
            case "--exclude": options.exclude.formUnion(try list(for: argument))
            case "--never": options.never += try list(for: argument).map(Options.expand)
            case "--roots": options.roots = try list(for: argument).map(Options.expand)
            case "--stale-days": options.staleDays = try days(for: argument)
            case "--project-days": options.projectDays = try days(for: argument)
            case "--download-days": options.downloadDays = try days(for: argument)
            case "--home": options.home = try value(for: argument)
            default: throw UsageError(message: "unknown option \(argument)")
            }
            index += 1
        }

        let known = Set(CullCatalog.entries.map(\.id))
        for id in (options.only ?? []).union(options.exclude) where !known.contains(id) {
            throw UsageError(message: "unknown category \"\(id)\". `cull --list` shows them.")
        }
        for id in options.include where !known.contains(id) && id != "rebuildable" {
            throw UsageError(message: "unknown category \"\(id)\". `cull --list` shows them.")
        }
        return options
    }

    /// Turns a path typed at the prompt into an absolute one. `~` is left for the engine to expand
    /// against the home folder it is actually using.
    static func expand(_ path: String) -> String {
        if path.hasPrefix("/") || path.hasPrefix("~") { return path }
        return FileManager.default.currentDirectoryPath + "/" + path
    }

    func selection(for report: ScanReport) -> Set<String> {
        var selection = report.defaultSelection
        for category in report.categories {
            let wholeTier = include.contains("rebuildable") && category.tier == .rebuildable
            if include.contains(category.id) || wholeTier {
                selection.formUnion(category.items.map(\.id))
            }
            if exclude.contains(category.id) {
                selection.subtract(category.items.map(\.id))
            }
        }
        return selection
    }
}

struct Terminal {
    let color: Bool
    let inputIsInteractive: Bool
    let errorIsInteractive: Bool
    let width: Int

    init(color requested: Bool?) {
        let outputIsInteractive = isatty(STDOUT_FILENO) != 0
        inputIsInteractive = isatty(STDIN_FILENO) != 0
        errorIsInteractive = isatty(STDERR_FILENO) != 0
        color = requested ?? (outputIsInteractive && ProcessInfo.processInfo.environment["NO_COLOR"] == nil)
        let columns = ProcessInfo.processInfo.environment["COLUMNS"].flatMap { Int($0) } ?? 88
        width = max(64, min(columns, 104))
    }

    func style(_ text: String, _ codes: String...) -> String {
        guard color else { return text }
        return "\u{1B}[\(codes.joined(separator: ";"))m\(text)\u{1B}[0m"
    }

    func bold(_ text: String) -> String { style(text, "1") }
    func dim(_ text: String) -> String { style(text, "2") }
    func green(_ text: String) -> String { style(text, "32") }
    func yellow(_ text: String) -> String { style(text, "33") }
    func red(_ text: String) -> String { style(text, "31") }

    static func status(_ text: String) {
        let clipped = String(text.prefix(78))
        FileHandle.standardError.write(Data("\r\u{1B}[2K\(clipped)".utf8))
    }

    static func clearStatus() {
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
    }
}

struct Printer {
    let terminal: Terminal
    let environment: CullEnvironment
    let verbose: Bool

    private static let previewCount = 6

    /// One line with the size right-aligned: `  ● Label  detail ........ 3.1 GB`.
    private func row(
        indent: Int, marker: String, label: String, detail: String? = nil, size: String,
        emphasized: Bool = false, dimmed: Bool = false
    ) -> String {
        let prefix = String(repeating: " ", count: indent) + marker + " "
        let sizeWidth = 10
        let room = terminal.width - prefix.count - sizeWidth - 1
        var shownLabel = label
        var shownDetail = detail.map { "  " + $0 } ?? ""
        if shownLabel.count > room {
            shownLabel = String(shownLabel.prefix(max(1, room - 1))) + "…"
            shownDetail = ""
        } else if shownLabel.count + shownDetail.count > room {
            shownDetail = String(shownDetail.prefix(max(0, room - shownLabel.count - 1))) + "…"
        }
        let padding = String(repeating: " ", count: max(1, room - shownLabel.count - shownDetail.count + 1))
        let paddedSize = String(repeating: " ", count: max(0, sizeWidth - size.count)) + size
        if dimmed { return prefix + terminal.dim(shownLabel + shownDetail + padding + paddedSize) }
        let styledLabel = emphasized ? terminal.bold(shownLabel) : shownLabel
        return prefix + styledLabel + terminal.dim(shownDetail) + padding + (emphasized ? terminal.bold(paddedSize) : paddedSize)
    }

    private func marker(selected: Int, of total: Int) -> String {
        if total > 0, selected == total { return terminal.green("●") }
        if selected == 0 { return terminal.dim("○") }
        return terminal.yellow("◐")
    }

    func printReport(_ report: ScanReport, selection: Set<String>, applied: Bool) {
        if environment.isSandbox {
            print(terminal.yellow("Sandbox home: \(environment.home)"))
        }
        if let disk = report.disk {
            let name = DiskSpace.volumeName(of: environment.home) ?? "Disk"
            var line = "\(terminal.bold(name)): \(Format.disk(disk)) (\(Format.percent(disk.availableFraction)) free)"
            switch disk.pressure {
            case .critical: line += "  " + terminal.red("critical")
            case .tight: line += "  " + terminal.yellow("getting tight")
            case .comfortable: break
            }
            print(line)
        }
        print("")

        if report.allItems.isEmpty {
            print("Nothing worth culling.")
        }

        for tier in Tier.allCases {
            let categories = report.categories(in: tier)
            guard !categories.isEmpty else { continue }
            let total = categories.reduce(0) { $0 + $1.totalBytes }
            print(row(
                indent: 0, marker: " ", label: tier.title.uppercased(), detail: tier.explanation,
                size: Format.bytes(total), emphasized: true
            ))
            for category in categories { printCategory(category, selection: selection) }
            print("")
        }

        if !report.advisories.isEmpty {
            print(terminal.bold("  ALSO LARGE") + terminal.dim("  Cull leaves these alone"))
            for advisory in report.advisories {
                print(row(indent: 2, marker: "·", label: advisory.title, detail: advisory.hint, size: Format.bytes(advisory.bytes)))
            }
            print("")
        }
        for note in report.notes {
            print(terminal.dim("Note: \(note)"))
        }

        let selectedBytes = report.bytes(selected: selection)
        print("Selected \(terminal.bold(Format.bytes(selectedBytes))) of \(Format.bytes(report.totalBytes)) found.")
        if !applied {
            print(selectedBytes > 0
                ? "Nothing was deleted. Run `cull --apply` to cull what is selected."
                : "Nothing was deleted.")
        }
    }

    private func printCategory(_ category: CullCategory, selection: Set<String>) {
        let selectedCount = category.items.filter { selection.contains($0.id) }.count
        let detail = category.note ?? (category.items.count > 1 ? Format.count(category.items.count, "item") : nil)
        print(row(
            indent: 2, marker: marker(selected: selectedCount, of: category.items.count),
            label: category.title, detail: detail, size: Format.bytes(category.totalBytes)
        ))
        let shown = verbose ? category.items : Array(category.items.prefix(Self.previewCount))
        for item in shown {
            var details: [String] = []
            if let used = Format.lastUsed(item, now: environment.now) { details.append(used.lowercased()) }
            if let caution = item.caution { details.append(caution) }
            if item.incomplete { details.append("partly unreadable") }
            print(row(
                indent: 6, marker: marker(selected: selection.contains(item.id) ? 1 : 0, of: 1),
                label: item.title, detail: details.isEmpty ? nil : details.joined(separator: " · "),
                size: Format.bytes(item.bytes)
            ))
        }
        if shown.count < category.items.count {
            let rest = category.items.dropFirst(shown.count)
            let bytes = rest.reduce(0) { $0 + $1.bytes }
            print(row(
                indent: 6, marker: " ", label: "and \(rest.count) more (-v lists them)",
                size: Format.bytes(bytes), dimmed: true
            ))
        }
    }

    func printSummary(_ summary: CullSummary) {
        print("")
        for outcome in summary.problems {
            print(terminal.red("  ✗ ") + outcome.title + terminal.dim("  " + (outcome.message ?? "failed")))
        }
        var parts = ["Culled \(terminal.bold(Format.bytes(summary.deletedBytes)))"]
        if summary.trashedBytes > 0 {
            parts.append("moved \(Format.bytes(summary.trashedBytes)) to the Trash (empty it to get that space back)")
        }
        print(parts.joined(separator: ", ") + ".")
        if let before = summary.diskBefore, let after = summary.diskAfter {
            print("\(Format.bytes(after.available)) available now, up from \(Format.bytes(before.available)).")
        }
        if !summary.problems.isEmpty {
            print(terminal.yellow("\(Format.count(summary.problems.count, "item")) could not be fully removed."))
        }
    }
}
