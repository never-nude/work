import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var auth: GoogleAuth
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $settings.nextNumber, in: 1...99_999) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Live stream \(settings.nextNumber)")
                                .font(.system(.headline, design: .rounded))
                            Text("Title of the next broadcast")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Set number")
                        Spacer()
                        TextField("1", value: $settings.nextNumber, format: .number.grouping(.never))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                } header: {
                    Text("Numbering")
                } footer: {
                    Text("Counts up by one each time a stream airs.")
                }

                Section {
                    Toggle("Go live when the app opens", isOn: $settings.goLiveOnOpen)
                    Picker("Visibility", selection: $settings.privacy) {
                        ForEach(Privacy.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Quality", selection: $settings.quality) {
                        ForEach(Quality.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Stabilization", selection: $settings.stabilization) {
                        ForEach(Stabilization.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Start on the front camera", isOn: $settings.useFrontCamera)
                } header: {
                    Text("Broadcast")
                } footer: {
                    Text("Hold the phone sideways when you start for a landscape stream. Leaving the app ends the stream. Steady adds no delay. Smoother and Smoothest crop more and hold video back (up to about a second) before sending, and if the phone is destroyed that last stretch never reaches YouTube.")
                }

                Section {
                    Text("Settings → Action Button → Shortcut → GoLive → Go Live. One press opens the app and starts the broadcast.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Action Button")
                }

                Section {
                    LabeledContent("Channel", value: settings.channelTitle.isEmpty ? "Connected" : settings.channelTitle)
                    Button("Sign out", role: .destructive) {
                        auth.signOut()
                        dismiss()
                    }
                } header: {
                    Text("YouTube")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: settings.nextNumber) { _, value in
            if value < 1 { settings.nextNumber = 1 }
        }
    }
}
