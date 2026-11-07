//
//  ExerciseMediaStore.swift
//  liteweight
//
//  Persistent on-device cache for ExerciseDB / Gym Visual GIFs.
//  Files are written once and never evicted so the library works offline
//  after the first successful download.
//

import Foundation
import ImageIO
import os.log
import UniformTypeIdentifiers
import WorkoutDataKit

final class ExerciseMediaStore {
    static let shared = ExerciseMediaStore()

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "me.joshpatra.liteweight.exercise-media", qos: .utility)
    private let log = OSLog(subsystem: "me.joshpatra.liteweight", category: "exercise-media")

    /// On-demand fetches (opening an exercise) may use cellular.
    private let interactiveSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Catalog prefetch waits for an inexpensive path (Wi-Fi) and never deletes files.
    private let prefetchSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    private var prefetchTask: Task<Void, Never>?
    private let cacheDirectoryOverride: URL?

    init(cacheDirectoryURL: URL? = nil) {
        cacheDirectoryOverride = cacheDirectoryURL
        try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private var directoryURL: URL {
        cacheDirectoryOverride ?? fileManager.appGroupContainerApplicationSupportURL
            .appendingPathComponent("ExerciseMedia", isDirectory: true)
    }

    func fileURL(for remoteURL: URL) -> URL {
        directoryURL.appendingPathComponent(cacheFileName(for: remoteURL), isDirectory: false)
    }

    func cachedData(for remoteURL: URL) -> Data? {
        let url = fileURL(for: remoteURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The activity publisher prepares this file before delivering the snapshot.
    /// Only cached media is eligible; widget rendering never depends on a download.
    func liveActivityArtworkFileName(for remoteURL: URL) -> String? {
        let fileName = liveActivityArtworkFileNameValue(for: remoteURL)
        guard let artworkURL = WorkoutLiveActivityArtwork.fileURL(for: fileName) else {
            return nil
        }
        guard fileManager.fileExists(atPath: artworkURL.path)
            || fileManager.fileExists(atPath: fileURL(for: remoteURL).path) else { return nil }
        return fileName
    }

    /// Returns persisted bytes, downloading and storing them when missing.
    func data(for remoteURL: URL) async -> Data? {
        if remoteURL.isFileURL { return try? Data(contentsOf: remoteURL) }
        if let cached = cachedData(for: remoteURL) {
            return cached
        }
        return await download(remoteURL, session: interactiveSession)
    }

    /// Lists read a persisted still, while the demonstration keeps its original
    /// animation. This uses only liteweight's current provider/cache, not OpenGym media.
    func stillData(for remoteURL: URL) async -> Data? {
        if remoteURL.isFileURL { return try? Data(contentsOf: remoteURL) }
        let destination = directoryURL.appendingPathComponent("still", isDirectory: true)
            .appendingPathComponent(cacheFileName(for: remoteURL) + ".png")
        if let cached = try? Data(contentsOf: destination) { return cached }
        guard let original = await data(for: remoteURL) else { return nil }
        let log = self.log
        return await withCheckedContinuation { continuation in
            ioQueue.async {
                if let cached = try? Data(contentsOf: destination) {
                    continuation.resume(returning: cached)
                    return
                }
                guard let source = CGImageSourceCreateWithData(original as CFData, nil),
                      let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    continuation.resume(returning: nil)
                    return
                }
                let bytes = NSMutableData()
                guard let encoder = CGImageDestinationCreateWithData(
                    bytes, UTType.png.identifier as CFString, 1, nil
                ) else {
                    continuation.resume(returning: nil)
                    return
                }
                CGImageDestinationAddImage(encoder, frame, nil)
                guard CGImageDestinationFinalize(encoder) else {
                    continuation.resume(returning: nil)
                    return
                }
                let result = bytes as Data
                do {
                    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try result.write(to: destination, options: .atomic)
                } catch {
                    os_log("Could not cache exercise still: %{public}@", log: log, type: .error, error.localizedDescription)
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// Fills any missing catalogue GIFs in the background. Safe to call on every launch.
    func prefetchCatalogue(from exercises: [Exercise]) {
        prefetchTask?.cancel()
        let urls = uniqueMediaURLs(in: exercises)
        prefetchTask = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            for url in urls {
                if Task.isCancelled { return }
                if self.cachedData(for: url) != nil { continue }
                _ = await self.download(url, session: self.prefetchSession)
            }
        }
    }

    private func uniqueMediaURLs(in exercises: [Exercise]) -> [URL] {
        var seen = Set<URL>()
        var urls: [URL] = []
        urls.reserveCapacity(exercises.count)
        for exercise in exercises {
            guard let url = exercise.imageURL ?? exercise.animationURL,
                  !url.isFileURL else { continue }
            if seen.insert(url).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    private func download(_ remoteURL: URL, session: URLSession) async -> Data? {
        if let cached = cachedData(for: remoteURL) {
            return cached
        }

        var request = URLRequest(url: remoteURL)
        request.setValue("image/gif,image/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty else { return nil }
            persist(data, for: remoteURL)
            return data
        } catch {
            os_log("Exercise media download failed for %{public}@: %{public}@", log: log, type: .info, remoteURL.absoluteString, error.localizedDescription)
            return cachedData(for: remoteURL)
        }
    }

    private func persist(_ data: Data, for remoteURL: URL) {
        let destination = fileURL(for: remoteURL)
        if fileManager.fileExists(atPath: destination.path) { return }

        ioQueue.sync {
            if fileManager.fileExists(atPath: destination.path) { return }
            let temporary = destination.appendingPathExtension("tmp")
            do {
                try data.write(to: temporary, options: .atomic)
                if fileManager.fileExists(atPath: destination.path) {
                    try? fileManager.removeItem(at: temporary)
                    return
                }
                try fileManager.moveItem(at: temporary, to: destination)
            } catch {
                try? fileManager.removeItem(at: temporary)
                os_log("Could not persist exercise media: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }
    }

    /// Prepare only the current/next exercise, off the main thread. Waiting here
    /// keeps the first activity render from racing the thumbnail write without
    /// pre-rendering the whole exercise catalogue or delaying on network access.
    func prepareLiveActivityArtwork(fileNames: [String]) async {
        guard !fileNames.isEmpty else { return }
        let sourceDirectory = directoryURL
        await withCheckedContinuation { continuation in
            ioQueue.async {
                let fileManager = FileManager.default
                for fileName in Set(fileNames) {
                    guard fileName.hasSuffix(".png"),
                          let destination = WorkoutLiveActivityArtwork.fileURL(for: fileName),
                          !fileManager.fileExists(atPath: destination.path) else { continue }
                    let sourceName = String(fileName.dropLast(4))
                    let source = sourceDirectory.appendingPathComponent(sourceName)
                    guard let data = try? Data(contentsOf: source) else { continue }
                    Self.persistLiveActivityArtwork(data, to: destination)
                }
                continuation.resume()
            }
        }
    }

    private static func persistLiveActivityArtwork(_ data: Data, to destination: URL) {
        let fileManager = FileManager.default
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 128
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return }

        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let temporary = destination.appendingPathExtension("tmp")
            try? fileManager.removeItem(at: temporary)
            guard let imageDestination = CGImageDestinationCreateWithURL(
                temporary as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else { return }
            CGImageDestinationAddImage(imageDestination, thumbnail, nil)
            guard CGImageDestinationFinalize(imageDestination) else {
                try? fileManager.removeItem(at: temporary)
                return
            }
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: temporary)
                return
            }
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            os_log(
                "Could not persist Live Activity artwork: %{public}@",
                log: OSLog(subsystem: "me.joshpatra.liteweight", category: "exercise-media"),
                type: .error,
                error.localizedDescription
            )
        }
    }

    private func liveActivityArtworkFileNameValue(for remoteURL: URL) -> String {
        cacheFileName(for: remoteURL) + ".png"
    }

    private func cacheFileName(for remoteURL: URL) -> String {
        let last = remoteURL.lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let filtered = last.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let name = String(filtered)
        if name.isEmpty || name == "." || name == ".." {
            return String(remoteURL.absoluteString.hashValue) + ".gif"
        }
        return name
    }
}
