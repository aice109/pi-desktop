//
//  SettingsView.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI

/// 偏好设置窗口（`Settings` scene，⌘,）。
struct SettingsView: View {
    @Environment(AppSettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }

            Section {
                Toggle("Reopen the last session", isOn: $settings.restoreLastSession)
            } header: {
                Text("Startup")
            } footer: {
                Text("Restores the session that was open when you quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show usage footer", isOn: $settings.showUsageFooter)
                Toggle("Show anchor panel", isOn: $settings.showAnchorPanel)
            } header: {
                Text("Chat")
            } footer: {
                Text(
                    "The usage footer shows context usage, tokens, and cost under the composer; the anchor panel lists turns on the right for quick navigation."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Confirm before deleting", isOn: $settings.confirmDeletion)
            } header: {
                Text("Sessions")
            } footer: {
                Text("Ask before moving a session to the Trash.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}

#Preview {
    SettingsView()
        .environment(AppSettingsStore(defaults: UserDefaults(suiteName: "SettingsPreview") ?? .standard))
}
