//
//  ExclusionManager.swift
//  CodeFusion
//
//  Created by Arnaud Dupuy on 2024-10-03.
//

import Foundation
import SwiftUI

class ExclusionManager: ObservableObject {
    @AppStorage("excludedItems") private var excludedItemsString: String = ""

    @Published private(set) var excludedItems: [String] = []

    init() {
        // Initialize excludedItems from the stored string
        self.excludedItems = excludedItemsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // Adds a new item to the exclusion list
    func addExcludedItem(_ item: String) {
        if !excludedItems.contains(item) {
            excludedItems.append(item)
            excludedItemsString = excludedItems.joined(separator: ",")
        }
    }

    // Removes an item from the exclusion list
    func removeExcludedItem(_ item: String) {
        excludedItems.removeAll { $0 == item }
        excludedItemsString = excludedItems.joined(separator: ",")
    }

    // Checks if a file or folder should be excluded
    func isExcluded(nodeName: String) -> Bool {
        let exclusionPatterns = excludedItems.map { exclusionPatternToRegex($0) }
        return exclusionPatterns.contains { pattern in
            let regex = try? NSRegularExpression(pattern: pattern)
            return regex?.firstMatch(in: nodeName, range: NSRange(location: 0, length: nodeName.utf16.count)) != nil
        }
    }

    // Converts exclusion patterns like "*.swift" to regex
    private func exclusionPatternToRegex(_ pattern: String) -> String {
        var regexPattern = NSRegularExpression.escapedPattern(for: pattern)
        regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")
        if !pattern.contains("*") {
            regexPattern = "^" + regexPattern + "$"
        }
        return regexPattern
    }
}
