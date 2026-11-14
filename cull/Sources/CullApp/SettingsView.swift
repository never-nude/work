import AppKit
import CullCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @AppStorage(AppSettings.Key.staleDays) private var staleDays = 14
    @AppStorage(AppSettings.Key.projectStaleDays) private var projectStaleDays = 30
    @AppStorage(AppSettings.Key.downloadsAgeDays) private var downloadsAgeDays = 90
    @AppStorage(AppSettings.Key.confirmBeforeCulling) private var confirmBeforeCulling = true

    @State private var customRoots: [String]? = AppSettings.projectRoots
    @State private var exclusions: [String] = AppSettings.exclusions
    @State private var folderProblem: String?

    var body: some View {
        Form {
            Section {
                dayPicker("Xcode build data, unbuilt for", selection: $staleDays)
                dayPicker("Project dependencies, untouched for", selection: $projectStaleDays)
                dayPicker("Downloads, untouched for", selection: $downloadsAgeDays)
            } header: {
                Text("What counts as stale")
            } footer: {
                Text("Stale build data and dependencies are pre-selected. Old downloads are only ever listed.")
            }

            Section {
                ForEach(shownRoots, id: \.self) { root in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(tilde(root))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if customRoots != nil {
                            Button {
                                remove(root: root)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Stop searching this folder")
                        }
                    }
                }
                if shownRoots.isEmpty {
                    Text("No project folders found.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Add Folder…") { addRoots() }
                    if customRoots != nil {
                        Button("Use the Usual Places") { setRoots(nil) }
                    }
                    Spacer()
                }
                if let folderProblem {
                    Text(folderProblem)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Project folders")
            } footer: {
                Text(customRoots == nil
                    ? "Cull searches the usual places for node_modules, .build, Pods and virtual environments in idle projects. Add a folder to choose your own."
                    : "Only these folders are searched for idle projects.")
            }

            Section {
                if exclusions.isEmpty {
                    Text("Nothing yet. Right-click any item in the list and choose Never Cull This.")
                        .foregroundStyle(.secondary)
                }
                ForEach(exclusions, id: \.self) { entry in
                    HStack {
                        Text(tilde(entry))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            exclusions.removeAll { $0 == entry }
                            AppSettings.exclusions = exclusions
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Offer this again")
                    }
                }
            } header: {
                Text("Never cull")
            }

            Section {
                Toggle("Ask before culling", isOn: $confirmBeforeCulling)
                LabeledContent("Full Disk Access") {
                    HStack(spacing: 10) {
                        let granted = model.environment?.hasFullDiskAccess ?? false
                        Label(granted ? "On" : "Off", systemImage: granted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(granted ? Color.green : Color.secondary)
                        Button("Open Settings…") { model.openFullDiskAccessSettings() }
                    }
                }
            } header: {
                Text("Safety")
            } footer: {
                Text("Cull only ever removes things inside your home folder, never as root, and personal files always go to the Trash. Changes here apply on the next scan.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 640)
        .onAppear {
            customRoots = AppSettings.projectRoots
            exclusions = AppSettings.exclusions
        }
    }

    private func dayPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(AppSettings.dayChoices, id: \.self) { days in
                Text("\(days) days").tag(days)
            }
        }
    }

    /// The custom folders, or the ones Cull finds by itself.
    private var shownRoots: [String] {
        if let customRoots { return customRoots }
        guard let environment = model.environment else { return [] }
        return Scanner(environment: environment, options: ScanOptions()).projectRoots()
    }

    private func tilde(_ path: String) -> String {
        Format.tilde(path, home: model.environment?.home ?? NSHomeDirectory())
    }

    private func setRoots(_ roots: [String]?) {
        customRoots = roots
        AppSettings.projectRoots = roots
        folderProblem = nil
    }

    private func remove(root: String) {
        setRoots((customRoots ?? []).filter { $0 != root })
    }

    private func addRoots() {
        let home = model.environment?.home ?? NSHomeDirectory()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: home)
        panel.prompt = "Add"
        panel.message = "Choose folders that hold your projects."
        guard panel.runModal() == .OK else { return }

        var roots = customRoots ?? shownRoots
        var rejected: [String] = []
        for url in panel.urls {
            let path = url.path
            // The engine refuses anything outside home, and home itself is too broad to walk.
            guard path.hasPrefix(home + "/") else {
                rejected.append(url.lastPathComponent)
                continue
            }
            if !roots.contains(path) { roots.append(path) }
        }
        setRoots(roots)
        if !rejected.isEmpty {
            folderProblem = "Skipped \(rejected.joined(separator: ", ")): Cull only works on folders inside your home folder."
        }
    }
}
