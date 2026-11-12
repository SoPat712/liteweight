//
//  PathCache.swift
//  MuscleMap
//
//  Created by Melih Colpan on 2026-02-09.
//  Copyright © 2026 Melih Colpan. All rights reserved.
//  Licensed under the MIT License.
//

import SwiftUI

final class PathCache: @unchecked Sendable {

    static let shared = PathCache()

    struct Key: Hashable {
        let svgPath: String
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
    }

    private var cache: [Key: Path] = [:]
    private let lock = NSLock()

    func path(
        for svgPath: String,
        scale: CGFloat,
        offsetX: CGFloat,
        offsetY: CGFloat
    ) -> Path {
        let key = Key(svgPath: svgPath, scale: scale, offsetX: offsetX, offsetY: offsetY)

        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let built = PathBuilder.buildPath(from: svgPath, scale: scale, offsetX: offsetX, offsetY: offsetY)

        lock.lock()
        if cache.count > 6000 { cache.removeAll(keepingCapacity: true) }
        cache[key] = built
        lock.unlock()

        return built
    }

    func contains(_ key: Key) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cache[key] != nil
    }

    func invalidate() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
