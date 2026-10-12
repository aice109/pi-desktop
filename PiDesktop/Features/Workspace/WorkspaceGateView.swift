//
//  WorkspaceGateView.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI
import UniformTypeIdentifiers

/// 未选择工作区时的引导页：提示用户先选择一个目录。
///
/// pi 的会话按工作目录分组，因此目录是进入应用的第一步。
struct WorkspaceGateView: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    @State private var isPickingFolder = false

    var body: some View {
        ContentUnavailableView {
            Label("Choose a Folder", systemImage: "folder.badge.plus")
        } description: {
            Text("Select a project folder to browse the pi sessions stored for that directory.")
        } actions: {
            Button("Choose Folder…") { isPickingFolder = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(minWidth: 520, minHeight: 400)
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleSelection
        )
    }

    private func handleSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // 沙盒已关闭（ADR-0003），此处通常返回 false；保留调用以便将来开启沙盒时仍正确。
            _ = url.startAccessingSecurityScopedResource()
            workspaceStore.setWorkspace(url)
        case .failure(let error):
            workspaceStore.report(error)
        }
    }
}

#Preview {
    WorkspaceGateView()
        .environment(WorkspaceStore(defaults: UserDefaults(suiteName: "WorkspaceGatePreview") ?? .standard))
}
