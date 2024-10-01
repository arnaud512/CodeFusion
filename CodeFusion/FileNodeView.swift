//
//  FileNodeView.swift
//  CodeFusion
//
//  Created by Arnaud Dupuy on 2024-09-30.
//

import SwiftUI

struct FileNodeView: View {
    let node: FileNode
    @Binding var expandedNodes: Set<URL>
    @Binding var selectedFiles: Set<URL>
    var level: Int

    @EnvironmentObject var exclusionManager: ExclusionManager
    @EnvironmentObject var viewModel: FileManagerViewModel

    var body: some View {
        let selectionState = self.selectionState(for: node)
        let toggleImageName = getToggleImageName(for: selectionState)

        HStack {
            if node.isDirectory {
                Image(systemName: expandedNodes.contains(node.url) ? "chevron.down" : "chevron.right")
                    .onTapGesture {
                        toggleExpandedState(for: node)
                    }
                    .frame(width: 12)
            } else {
                Spacer().frame(width: 18)  // Align with folder icons
            }

            Image(systemName: node.isDirectory ? "folder" : "doc")
            Text(node.url.lastPathComponent)
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: toggleImageName)
                .onTapGesture {
                    toggleSelection(for: node)
                }
        }
        .contentShape(Rectangle())  // Makes the entire row tappable
        .onTapGesture {
            handleTap(for: node)
        }
        .padding(.leading, CGFloat(level * 20))  // Indentation based on level
        .contextMenu {  // Context menu for right-click
            if node.isDirectory {
                Button("Exclude \(node.url.lastPathComponent)") {
                    excludeFolder(node)
                }
            } else {
                Button("Exclude *.\(node.url.pathExtension)") {
                    excludeFileExtension(node)
                }
                Button("Exclude \(node.url.lastPathComponent)") {
                    excludeFileName(node)
                }
            }
        }

        if node.isDirectory && expandedNodes.contains(node.url), let children = node.children {
            ForEach(sortedChildren(children)) { child in
                FileNodeView(node: child,
                             expandedNodes: $expandedNodes,
                             selectedFiles: $selectedFiles,
                             level: level + 1)
                    .environmentObject(viewModel)  // Pass the viewModel down
                    .environmentObject(exclusionManager)  // Pass the exclusionManager down
            }
        }
    }

    func handleTap(for node: FileNode) {
        if node.isDirectory {
            toggleExpandedState(for: node)
        } else {
            toggleSelection(for: node)
        }
    }

    func toggleExpandedState(for node: FileNode) {
        if expandedNodes.contains(node.url) {
            expandedNodes.remove(node.url)
        } else {
            expandedNodes.insert(node.url)
        }
    }

    func sortedChildren(_ children: [FileNode]) -> [FileNode] {
        children.sorted {
            if $0.isDirectory && !$1.isDirectory {
                return true
            } else if !$0.isDirectory && $1.isDirectory {
                return false
            } else {
                return $0.url.lastPathComponent.lowercased() < $1.url.lastPathComponent.lowercased()
            }
        }
    }

    func selectionState(for node: FileNode) -> SelectionState {
        if node.isDirectory {
            guard let children = node.children, !children.isEmpty else { return .unselected }
            let childStates = children.map { selectionState(for: $0) }
            if childStates.allSatisfy({ $0 == .selected }) {
                return .selected
            } else if childStates.allSatisfy({ $0 == .unselected }) {
                return .unselected
            } else {
                return .partial
            }
        } else {
            return selectedFiles.contains(node.url) ? .selected : .unselected
        }
    }

    func toggleSelection(for node: FileNode) {
        if node.isDirectory {
            if self.selectionState(for: node) == .selected {
                deselectAll(in: node)
            } else {
                selectAll(in: node)
            }
        } else {
            if self.selectedFiles.contains(node.url) {
                self.selectedFiles.remove(node.url)
            } else {
                self.selectedFiles.insert(node.url)
            }
        }
    }

    func selectAll(in node: FileNode) {
        if node.isDirectory, let children = node.children {
            for child in children {
                selectAll(in: child)
            }
        } else {
            selectedFiles.insert(node.url)
        }
    }

    func deselectAll(in node: FileNode) {
        if node.isDirectory, let children = node.children {
            for child in children {
                deselectAll(in: child)
            }
        } else {
            selectedFiles.remove(node.url)
        }
    }

    func getToggleImageName(for selectionState: SelectionState) -> String {
        switch selectionState {
        case .unselected: return "circle"
        case .selected: return "circle.fill"
        case .partial: return "circle.dotted"
        }
    }

    // MARK: - Exclusion Handlers

    private func excludeFileExtension(_ node: FileNode) {
        let fileExtension = "*.\(node.url.pathExtension)"
        exclusionManager.addExcludedItem(fileExtension)
        refreshDirectoryContents()
    }

    private func excludeFileName(_ node: FileNode) {
        let fileName = node.url.lastPathComponent
        exclusionManager.addExcludedItem(fileName)
        refreshDirectoryContents()
    }

    private func excludeFolder(_ node: FileNode) {
        let folderName = node.url.lastPathComponent
        exclusionManager.addExcludedItem(folderName)
        refreshDirectoryContents()
    }

    private func refreshDirectoryContents() {
        if let rootURL = viewModel.rootNodes.first?.url {
            Task {
                viewModel.loadDirectoryContents(at: rootURL, expandedNodes: $expandedNodes)
            }
        }
    }
}
