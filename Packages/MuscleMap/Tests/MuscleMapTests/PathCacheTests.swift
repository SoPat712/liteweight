import XCTest
import SwiftUI
@testable import MuscleMap

final class PathCacheTests: XCTestCase {

    func testCacheReturnsSamePath() {
        let cache = PathCache()
        let svg = "M 0 0 L 100 100"
        let path1 = cache.path(for: svg, scale: 1.0, offsetX: 0, offsetY: 0)
        let path2 = cache.path(for: svg, scale: 1.0, offsetX: 0, offsetY: 0)
        // Both should be equivalent (cached)
        XCTAssertEqual(path1.boundingRect, path2.boundingRect)
    }

    func testCacheDifferentScalesAreDifferent() {
        let cache = PathCache()
        let svg = "M 0 0 L 100 100"
        let path1 = cache.path(for: svg, scale: 1.0, offsetX: 0, offsetY: 0)
        let path2 = cache.path(for: svg, scale: 2.0, offsetX: 0, offsetY: 0)
        XCTAssertNotEqual(path1.boundingRect, path2.boundingRect)
    }

    func testCacheKeysIncludePathAndOffsets() {
        let cache = PathCache()
        let first = cache.path(for: "M 0 0 L 100 100", scale: 1, offsetX: 0, offsetY: 0)
        let different = cache.path(for: "M 0 0 L 50 50", scale: 1, offsetX: 0, offsetY: 0)
        let shiftedX = cache.path(for: "M 0 0 L 100 100", scale: 1, offsetX: 10, offsetY: 0)
        let shiftedY = cache.path(for: "M 0 0 L 100 100", scale: 1, offsetX: 0, offsetY: 10)
        XCTAssertNotEqual(first.boundingRect, different.boundingRect)
        XCTAssertEqual(shiftedX.boundingRect, first.boundingRect.offsetBy(dx: 10, dy: 0))
        XCTAssertEqual(shiftedY.boundingRect, first.boundingRect.offsetBy(dx: 0, dy: 10))
    }

    func testRenderersShareCachedPaths() throws {
        let cache = PathCache.shared
        cache.invalidate()
        defer { cache.invalidate() }
        let viewBox = BodyPathProvider.viewBox(gender: .male, side: .front)
        let size = viewBox.size
        let part = try XCTUnwrap(BodyPathProvider.paths(gender: .male, side: .front).first { $0.slug.muscle == .chest })
        let key = PathCache.Key(svgPath: try XCTUnwrap(part.allPaths.first), scale: 1,
                                offsetX: -viewBox.origin.x, offsetY: -viewBox.origin.y)
        let first = BodyRenderer(gender: .male, side: .front, highlights: [:], style: .default, selectedMuscles: [])
        let second = BodyRenderer(gender: .male, side: .front, highlights: [:], style: .default, selectedMuscles: [])

        XCTAssertFalse(cache.contains(key))
        let bounds = try XCTUnwrap(first.boundingRect(for: .chest, in: size))
        XCTAssertTrue(cache.contains(key))
        XCTAssertEqual(second.boundingRect(for: .chest, in: size), bounds)
        XCTAssertTrue(cache.contains(key))
    }

    func testCacheClearsAfterEntryLimit() {
        let cache = PathCache()
        let svg = "M 0 0 L 100 100"
        let first = PathCache.Key(svgPath: svg, scale: 1, offsetX: 0, offsetY: 0)
        for offset in 0...6000 {
            let _ = cache.path(for: svg, scale: 1, offsetX: CGFloat(offset), offsetY: 0)
        }
        XCTAssertTrue(cache.contains(first))
        let _ = cache.path(for: svg, scale: 1, offsetX: 6001, offsetY: 0)
        XCTAssertFalse(cache.contains(first))
        XCTAssertTrue(cache.contains(PathCache.Key(svgPath: svg, scale: 1, offsetX: 6001, offsetY: 0)))
    }

    func testCacheInvalidation() {
        let cache = PathCache()
        let svg = "M 0 0 L 100 100"
        let _ = cache.path(for: svg, scale: 1.0, offsetX: 0, offsetY: 0)
        cache.invalidate()
        // After invalidation, should still work (rebuild from scratch)
        let path = cache.path(for: svg, scale: 1.0, offsetX: 0, offsetY: 0)
        XCTAssertFalse(path.isEmpty)
    }

    func testCacheThreadSafety() {
        let cache = PathCache()
        let svg = "M 0 0 L 100 100 Z"
        let expectation = XCTestExpectation(description: "Concurrent cache access")
        expectation.expectedFulfillmentCount = 10

        for i in 0..<10 {
            DispatchQueue.global().async {
                let scale = CGFloat(i + 1) * 0.1
                let _ = cache.path(for: svg, scale: scale, offsetX: 0, offsetY: 0)
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5.0)
    }
}
