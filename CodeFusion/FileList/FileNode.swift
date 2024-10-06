//
//  FileNode.swift
//  CodeFusion
//
//  Created by Arnaud Dupuy on 2024-09-30.
//

import Foundation

struct FileNode: Identifiable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]? = nil
}
