//
//  ContentView.swift
//  CodeFusion
//
//  Created by Arnaud Dupuy on 2024-09-30.
//

import SwiftUI

struct ContentView: View {
    @State private var expandedNodes: Set<URL> = []
    @State private var isCopied: Bool = false
    @AppStorage("pathOption") private var pathOptionRawValue: String = "full"
    @EnvironmentObject var exclusionManager: ExclusionManager
    @EnvironmentObject var viewModel: FileManagerViewModel
    @State private var tokenCount: Int = 0

    var pathOption: PathOption {
        if pathOptionRawValue == "relative", let rootURL = viewModel.rootNodes.first?.url {
            return .relative(baseURL: rootURL)
        } else {
            return .full
        }
    }

    var body: some View {
        NavigationView {
            if viewModel.rootNodes.isEmpty {
                VStack {
                    Text("No directory selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button(action: {
                        viewModel.pickDirectory(expandedNodes: $expandedNodes)
                    }) {
                        Label("Open Directory", systemImage: "folder")
                    }
                    .padding()
                }
                .frame(minWidth: 300)
            } else {
                VStack {
                    FileListView(expandedNodes: $expandedNodes)
                        .frame(minWidth: 300)
                }
            }

            VStack {
                if viewModel.isContentLoading {
                    ProgressView("Loading file content...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                } else if !viewModel.selectedFiles.isEmpty {
                    ScrollView {
                        LazyVStack {
                            ForEach(Array(viewModel.selectedFiles), id: \.self) { url in
                                if let content = viewModel.fileContents[url] {
                                    VStack(alignment: .leading) {
                                        Text("### START OF FILE: \(url.lastPathComponent) ###")
                                            .font(.headline)
                                        TextEditor(text: .constant(content))
                                            .frame(minHeight: 200)
                                        Text("### END OF FILE: \(url.lastPathComponent) ###")
                                            .font(.headline)
                                    }
                                    .padding()
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(8)
                                } else {
                                    Text("Unable to load content for \(url.lastPathComponent)")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding()
                        }
                    }
                } else {
                    Text("No files selected")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .onChange(of: viewModel.selectedFiles) {
            Task {
                await viewModel.loadContentsOfSelectedFiles()
                tokenCount = viewModel.calculateTokenCount(withPathOption: pathOption)
            }
        }
        .onChange(of: exclusionManager.excludedItems) {
            if let rootURL = viewModel.rootNodes.first?.url {
                viewModel.loadDirectoryContents(at: rootURL, expandedNodes: $expandedNodes)
                viewModel.selectedFiles = viewModel.selectedFiles.filter { url in
                    !exclusionManager.isExcluded(nodeName: url.lastPathComponent)
                }
            }
        }
        .toolbar(content: mainToolbar)
    }

    private func mainToolbar() -> some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            Spacer()
            Text("Tokens: ~\(tokenCount)")
                .font(.caption)
                .foregroundStyle(.gray)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.gray.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Button(action: {
                viewModel.copySelectedFilesToClipboard(withPathOption: pathOption)
                isCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    isCopied = false
                }
            }) {
                Label(isCopied ? "Copied!" : "Copy Code", systemImage: isCopied ? "checkmark" : "doc.on.doc")
            }
            .disabled(viewModel.selectedFiles.isEmpty)
            .padding()
        }
    }
}
