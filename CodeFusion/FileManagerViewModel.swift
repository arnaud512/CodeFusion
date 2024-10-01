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
    @Published var isLoading: Bool = false
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
        isLoading = true
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
            self.isLoading = false
        }
    }

    @MainActor
    private func createFileNode(from url: URL) async -> FileNode? {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        let nodeName = url.lastPathComponent

        // Check exclusion with the centralized exclusion manager
        if exclusionManager.isExcluded(nodeName: nodeName) {
            return nil  // Exclude this file or folder
        }

        if isDirectory.boolValue {
            let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            let children = await contents.asyncCompactMap { await createFileNode(from: $0) }

            if !children.isEmpty {
                return FileNode(url: url, isDirectory: true, children: children)
            } else {
                return nil  // Exclude empty directories
            }
        } else {
            return FileNode(url: url, isDirectory: false)
        }
    }

    // Grep search implementation
    func grepSearch(in directory: URL, query: String, caseSensitive: Bool) async -> [URL] {
        let task = Process()
        let pipe = Pipe()

        task.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        task.arguments = [
            caseSensitive ? "" : "-i",  // Case sensitivity
            "-rl",  // Search recursively and return matching file names
            query,
            directory.path
        ]
        task.standardOutput = pipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let filePaths = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            return filePaths.map { URL(fileURLWithPath: $0) }
        } catch {
            print("Grep command failed: \(error)")
            return []
        }
    }

    // Setup debounce to delay filtering until user stops typing
    private func setupFilterDebounce() {
        Publishers.CombineLatest($nameFilterQuery, $contentFilterQuery)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.applyFiltering()  // Trigger filtering whenever either query changes
            }
            .store(in: &cancellables)
    }

    // Perform the grep search and update filtered files
    private func performContentSearch(query: String, at directory: URL) async {
        guard !query.isEmpty else { return }

        isLoading = true
        let caseSensitive = isContentFilterCaseSensitive
        let matchedURLs = await grepSearch(in: directory, query: query, caseSensitive: caseSensitive)

        // Filter rootNodes based on grep result
        filteredNodes = rootNodes.filter { node in
            matchedURLs.contains(where: { url in url.path.hasPrefix(node.url.path) })
        }

        isLoading = false
    }

    func loadContentsOfSelectedFiles() async {
        isLoading = true
        for url in selectedFiles {
            await self.loadContent(of: url)
        }
        isLoading = false
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

    private func applyFiltering() {
        if nameFilterQuery.isEmpty && contentFilterQuery.isEmpty {
            filteredNodes = rootNodes
        } else {
            filteredNodes = rootNodes.compactMap {
                filterNode($0, nameQuery: nameFilterQuery, contentQuery: contentFilterQuery, isNameFilterCaseSensitive: isNameFilterCaseSensitive, isContentFilterCaseSensitive: isContentFilterCaseSensitive)
            }
        }
    }

    private func filterNode(_ node: FileNode, nameQuery: String, contentQuery: String, isNameFilterCaseSensitive: Bool, isContentFilterCaseSensitive: Bool) -> FileNode? {
        if node.isDirectory {
            let filteredChildren = node.children?.compactMap {
                filterNode($0, nameQuery: nameQuery, contentQuery: contentQuery, isNameFilterCaseSensitive: isNameFilterCaseSensitive, isContentFilterCaseSensitive: isContentFilterCaseSensitive)
            } ?? []
            if !filteredChildren.isEmpty {
                return FileNode(url: node.url, isDirectory: true, children: filteredChildren)
            }
        } else {
            let fileNameMatches: Bool
            if isNameFilterCaseSensitive {
                fileNameMatches = nameQuery.isEmpty || node.url.lastPathComponent.contains(nameQuery)
            } else {
                fileNameMatches = nameQuery.isEmpty || node.url.lastPathComponent.lowercased().contains(nameQuery.lowercased())
            }

            let fileContentMatches: Bool
            if contentQuery.isEmpty {
                fileContentMatches = true
            } else {
                if let content = fileContents[node.url] {
                    fileContentMatches = isContentFilterCaseSensitive ? content.contains(contentQuery) : content.lowercased().contains(contentQuery.lowercased())
                } else {
                    Task {
                        await loadContent(of: node.url)
                        objectWillChange.send()  // Trigger a UI update once content is loaded
                    }
                    fileContentMatches = false
                }
            }

            if (fileNameMatches && contentQuery.isEmpty) || (fileContentMatches && nameQuery.isEmpty) || (fileNameMatches && fileContentMatches) {
                return node
            }
        }
        return nil
    }

    func loadContent(of url: URL) async {
        if fileContents[url] != nil {
            return
        }

        if isTextFile(url: url) {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                await MainActor.run {
                    self.fileContents[url] = content
                    objectWillChange.send()
                }
            } catch {
                print("Failed to load content for file: \(error)")
            }
        } else {
            await MainActor.run {
                self.fileContents[url] = "Binary file skipped: \(url.lastPathComponent)"
                objectWillChange.send()
            }
            print("Skipping binary file: \(url.lastPathComponent)")
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
