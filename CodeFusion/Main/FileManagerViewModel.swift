//
//  FileManagerViewModel.swift
//  CodeFusion
//
//  Created by Arnaud Dupuy on 2024-10-03.
//

import SwiftUI
import Combine

@MainActor
class FileManagerViewModel: ObservableObject {
    @Published var rootNodes: [FileNode] = []
    @Published var filteredNodes: [FileNode] = []
    @Published var selectedFiles: Set<URL> = []
    @Published var fileContents: [URL: String] = [:]
    @Published var isContentLoading: Bool = false
    @Published var isFiltering: Bool = false
    @Published var nameFilterQuery: String = ""
    @Published var contentFilterQuery: String = ""
    @Published var isNameFilterCaseSensitive: Bool = false
    @Published var isContentFilterCaseSensitive: Bool = false

    private var fileModificationDates: [URL: Date] = [:]
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let exclusionManager: ExclusionManager

    init(exclusionManager: ExclusionManager) {
        self.exclusionManager = exclusionManager
        startFileUpdateTimer()
        setupFilterDebounce()
    }

    deinit {
        timer?.invalidate()
    }

    func pickDirectory(expandedNodes: Binding<Set<URL>>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            selectedFiles.removeAll()
            nameFilterQuery = ""
            contentFilterQuery = ""
            loadDirectoryContents(at: url, expandedNodes: expandedNodes)
        }
    }

    func loadDirectoryContents(at url: URL, expandedNodes: Binding<Set<URL>>) {
        isFiltering = true
        Task {
            if let node = await self.createFileNode(from: url) {
                self.rootNodes = [node]
                if node.isDirectory {
                    expandedNodes.wrappedValue.insert(node.url)
                }
            } else {
                self.rootNodes = []
            }
            applyFiltering()
            self.isFiltering = false
        }
    }

    @MainActor
    private func createFileNode(from url: URL) async -> FileNode? {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        let nodeName = url.lastPathComponent

        if exclusionManager.isExcluded(nodeName: nodeName) {
            return nil
        }

        if isDirectory.boolValue {
            let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            let children = await contents.asyncCompactMap { await createFileNode(from: $0) }

            if !children.isEmpty {
                return FileNode(url: url, isDirectory: true, children: children)
            } else {
                return nil
            }
        } else {
            return FileNode(url: url, isDirectory: false)
        }
    }

    func grepSearch(in directory: URL, query: String, caseSensitive: Bool, ignoredPatterns: [String]) async -> [URL] {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/grep")

        var arguments: [String] = []
        if !caseSensitive {
            arguments.append("-i")
        }
        arguments.append("-rl")
        arguments.append(query)

        for pattern in ignoredPatterns {
            if pattern.hasSuffix("/") {
                arguments.append("--exclude-dir=\(pattern)")
            } else {
                arguments.append("--exclude=\(pattern)")
            }
        }

        arguments.append(directory.path)

        task.arguments = arguments
        task.standardOutput = pipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let filePaths = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            return filePaths.map { URL(fileURLWithPath: $0) }
        } catch {
            return []
        }
    }

    private func setupFilterDebounce() {
        Publishers.CombineLatest($nameFilterQuery, $contentFilterQuery)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.applyFiltering()
            }
            .store(in: &cancellables)
    }

    private func applyFiltering() {
        isFiltering = true
        filteredNodes = []

        if !nameFilterQuery.isEmpty {
            filteredNodes = rootNodes.compactMap {
                filterNode($0, nameQuery: nameFilterQuery, isNameFilterCaseSensitive: isNameFilterCaseSensitive)
            }
        } else {
            filteredNodes = rootNodes
        }

        if !contentFilterQuery.isEmpty, let rootURL = rootNodes.first?.url {
            performContentSearch(query: contentFilterQuery, at: rootURL)
        } else {
            isFiltering = false
        }
    }

    private func filterNode(_ node: FileNode, nameQuery: String, isNameFilterCaseSensitive: Bool) -> FileNode? {
        if node.isDirectory {
            let filteredChildren = node.children?.compactMap {
                filterNode($0, nameQuery: nameQuery, isNameFilterCaseSensitive: isNameFilterCaseSensitive)
            } ?? []
            if !filteredChildren.isEmpty {
                return FileNode(url: node.url, isDirectory: true, children: filteredChildren)
            }
        } else {
            let fileNameMatches = isNameFilterCaseSensitive
                ? node.url.lastPathComponent.contains(nameQuery)
                : node.url.lastPathComponent.lowercased().contains(nameQuery.lowercased())

            if fileNameMatches {
                return node
            }
        }
        return nil
    }

    private func performContentSearch(query: String, at directory: URL) {
        Task {
            let caseSensitive = isContentFilterCaseSensitive
            let ignoredPatterns = exclusionManager.excludedItems

            let matchedURLs = await grepSearch(in: directory, query: query, caseSensitive: caseSensitive, ignoredPatterns: ignoredPatterns)

            await MainActor.run {
                filteredNodes = filterNodesWithMatchingFiles(in: rootNodes, matchingURLs: matchedURLs)
                isFiltering = false
            }
        }
    }

    private func filterNodesWithMatchingFiles(in nodes: [FileNode], matchingURLs: [URL]) -> [FileNode] {
        return nodes.compactMap { node in
            if node.isDirectory {
                let filteredChildren = filterNodesWithMatchingFiles(in: node.children ?? [], matchingURLs: matchingURLs)
                if !filteredChildren.isEmpty {
                    return FileNode(url: node.url, isDirectory: true, children: filteredChildren)
                }
            } else if matchingURLs.contains(where: { $0.path == node.url.path }) {
                return node
            }
            return nil
        }
    }

    func loadContentsOfSelectedFiles() async {
        isContentLoading = true
        for url in selectedFiles {
            await self.loadContent(of: url)
        }
        isContentLoading = false
    }

    func copySelectedFilesToClipboard(withPathOption pathOption: PathOption) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selectedFilesString(withPathOption: pathOption), forType: .string)
    }

    private func selectedFilesString(withPathOption pathOption: PathOption) -> String {
        var combinedContent = ""
        for url in selectedFiles {
            if let content = fileContents[url] {
                let displayPath: String
                switch pathOption {
                case .full:
                    displayPath = url.path
                case .relative(let baseURL):
                    displayPath = url.path.replacingOccurrences(of: baseURL.path + "/", with: "")
                }
                combinedContent += "### START OF FILE: \(displayPath) ###\n\(content)\n### END OF FILE: \(displayPath) ###\n\n"
            }
        }
        return combinedContent
    }

    private func startFileUpdateTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                await self.checkForFileUpdates()
            }
        }
    }

    private func checkForFileUpdates() async {
        for url in selectedFiles {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let modificationDate = attributes[.modificationDate] as? Date else {
                continue
            }
            if let lastKnownDate = fileModificationDates[url], modificationDate > lastKnownDate {
                await self.loadContent(of: url)
            } else {
                fileModificationDates[url] = modificationDate
            }
        }
    }

    func calculateTokenCount(withPathOption pathOption: PathOption) -> Int {
        let tokenCount = approximateBPETokenCount(for: selectedFilesString(withPathOption: pathOption))
        return ((tokenCount + 50) / 100) * 100
    }

    func approximateBPETokenCount(for text: String) -> Int {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let regexPattern = "[\\w]+|[^\u{00}-\u{7F}]+|[^\u{0000}-\u{007F}]+|\\S"

        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: []) else {
            return 0
        }

        let matches = regex.matches(in: cleanedText, options: [], range: NSRange(location: 0, length: cleanedText.utf16.count))
        var tokenCount = 0
        for match in matches {
            let wordRange = Range(match.range, in: cleanedText)!
            let word = String(cleanedText[wordRange])
            if word.count > 4 {
                tokenCount += (word.count / 4) + 1
            } else {
                tokenCount += 1
            }
        }
        return tokenCount
    }

    func loadContent(of url: URL) async {
        if fileContents[url] != nil {
            return
        }

        if isTextFile(url: url) {
            let content = try? String(contentsOf: url, encoding: .utf8)
            await MainActor.run {
                self.fileContents[url] = content
                objectWillChange.send()
            }
        } else {
            await MainActor.run {
                self.fileContents[url] = "Binary file skipped: \(url.lastPathComponent)"
                objectWillChange.send()
            }
        }
    }

    func isTextFile(url: URL) -> Bool {
        do {
            let fileContent = try Data(contentsOf: url)
            let isBinary = fileContent.contains(0)
            return !isBinary
        } catch {
            return false
        }
    }
}
