//
//  FileListView.swift
//  CodeFusion
//
//  Created by Arnaud Dupuy on 2024-10-03.
//

import SwiftUI

struct FileListView: View {
    @Binding var expandedNodes: Set<URL>
    @EnvironmentObject var viewModel: FileManagerViewModel

    var body: some View {
        VStack {
            List {
                if viewModel.isFiltering {
                    ProgressView("Filtering files...")
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(viewModel.filteredNodes) { node in
                        FileNodeView(
                            node: node,
                            expandedNodes: $expandedNodes,
                            selectedFiles: $viewModel.selectedFiles,
                            level: 0
                        )
                    }
                }
            }
            .listStyle(SidebarListStyle())

            VStack {
                HStack {
                    TextField("Filter by name", text: $viewModel.nameFilterQuery)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button(action: {
                        viewModel.isNameFilterCaseSensitive.toggle()
                    }) {
                        Image(systemName: "textformat")
                            .foregroundColor(viewModel.isNameFilterCaseSensitive ? .blue : .gray)
                    }
                    .help("Toggle case sensitivity for name filter")
                }

                HStack {
                    TextField("Filter by content", text: $viewModel.contentFilterQuery)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button(action: {
                        viewModel.isContentFilterCaseSensitive.toggle()
                    }) {
                        Image(systemName: "textformat")
                            .foregroundColor(viewModel.isContentFilterCaseSensitive ? .blue : .gray)
                    }
                    .help("Toggle case sensitivity for content filter")
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    viewModel.pickDirectory(expandedNodes: $expandedNodes)
                }) {
                    Label("Open Folder", systemImage: "folder")
                }
            }

            ToolbarItem(placement: .automatic) {
                SettingsLink(
                    label: {
                        Label("Settings", systemImage: "gear")
                    }
                )
            }
        }
    }

    private func toggleSidebar() {
        #if os(macOS)
        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
        #endif
    }
}
