//
//  Array+extensions.swift
//  CodeFusion
//
//  Created by Arnaud Dupuy on 2024-10-03.
//

import Foundation

extension Array {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var results = [T]()
        for item in self {
            let result = await transform(item)
            results.append(result)
        }
        return results
    }

    func asyncCompactMap<T>(_ transform: (Element) async -> T?) async -> [T] {
        var results = [T]()
        for item in self {
            if let result = await transform(item) {
                results.append(result)
            }
        }
        return results
    }
}
