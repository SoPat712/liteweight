//
//  BackupFileStore.swift
//  liteweight
//
//  Created by Karim Abou Zeid on 28.10.19.
//  Copyright © 2019 Karim Abou Zeid Software. All rights reserved.
//

import Foundation
import UIKit
import os.log

class BackupFileStore: ObservableObject {
    static let shared = BackupFileStore()
    private static let maximumDownloadPollAttempts = 15
    
    private init() {}
    
    struct BackupFile: Identifiable {
        let url: URL
        let creationDate: Date
        let fileSize: Int
        let deviceName: String
        
        var id: URL { url }
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unavailable(String)
    }
    
    @Published var backups = [BackupFile]()
    @Published private(set) var loadState: LoadState = .idle
    
    func fetchBackups() {
        fetchBackups(downloadPollAttempt: 0)
    }

    private func fetchBackups(downloadPollAttempt: Int) {
        os_log("Fetching backup file list", log: .backup, type: .default)
        DispatchQueue.main.async {
            self.loadState = .loading
        }

        UbiquityContainer.backupsUrl { result in
            let url: URL
            do {
                url = try result.get()
            } catch {
                self.finishLoading(with: .unavailable(Self.availabilityMessage(for: error)), backups: [])
                return
            }
            
            let deviceDirectoryUrls: [URL]
            do {
                deviceDirectoryUrls = try FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .nameKey]
                )
            } catch {
                self.finishLoading(with: .unavailable(Self.availabilityMessage(for: error)), backups: [])
                return
            }

            var startedDownloads = false
            let backups: [[BackupFile]] = deviceDirectoryUrls.compactMap { deviceDirectoryUrl in
                guard let resourceValues = try? deviceDirectoryUrl.resourceValues(forKeys: [.isDirectoryKey, .nameKey]) else { return nil }
                guard resourceValues.isDirectory ?? false else { return nil }
                guard let deviceName = resourceValues.name else { return nil }
                
                guard let backupUrls = try? FileManager.default.contentsOfDirectory(at: deviceDirectoryUrl, includingPropertiesForKeys: [.typeIdentifierKey, .creationDateKey, .totalFileSizeKey]) else { return nil }
                return backupUrls.compactMap { backupUrl in
                    guard let resourceValues = try? backupUrl.resourceValues(forKeys: [.typeIdentifierKey, .creationDateKey, .totalFileSizeKey]) else { return nil }
                    let uti = resourceValues.typeIdentifier
                    if uti == "com.apple.icloud-file-fault" {
                        do {
                            // if there are undownloaded files, download them and call fetchBackups() again after a short delay
                            os_log("Starting download of iCloud file %@", log: .backup, type: .default, backupUrl.path)
                            try FileManager.default.startDownloadingUbiquitousItem(at: backupUrl)
                            startedDownloads = true
                        } catch {
                            os_log("Could not download iCloud file %@:", log: .backup, type: .fault, backupUrl.path, error.localizedDescription)
                        }
                        return nil
                    }
                    guard LiteweightBackup.acceptsBackupFile(typeIdentifier: uti, pathExtension: backupUrl.pathExtension) else { return nil }
                    guard let creationDate = resourceValues.creationDate else { return nil }
                    guard let totalFileSize = resourceValues.totalFileSize else { return nil }
                    return BackupFile(url: backupUrl, creationDate: creationDate, fileSize: totalFileSize, deviceName: deviceName)
                }
            }

            let sortedBackups = backups
                .flatMap { $0 }
                .sorted { $0.creationDate > $1.creationDate }
            if startedDownloads {
                guard downloadPollAttempt < Self.maximumDownloadPollAttempts else {
                    self.finishLoading(
                        with: .unavailable(
                            "Some iCloud backups are taking longer than expected to download. Check your connection, then try again."
                        ),
                        backups: sortedBackups
                    )
                    return
                }

                self.finishLoading(with: .loading, backups: sortedBackups)
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(1)) {
                    self.fetchBackups(downloadPollAttempt: downloadPollAttempt + 1)
                }
            } else {
                self.finishLoading(with: .loaded, backups: sortedBackups)
            }
        }
    }

    private func finishLoading(with state: LoadState, backups: [BackupFile]) {
        DispatchQueue.main.async {
            self.backups = backups
            self.loadState = state
        }
    }

    private static func availabilityMessage(for error: Error) -> String {
        if error is UbiquityContainer.UbiquityContainerError {
            return "iCloud Drive is not available to liteweight. Check that you are signed in to iCloud and that iCloud Drive is enabled, then try again."
        }

        os_log(
            "Could not read iCloud backups: %@",
            log: .backup,
            type: .error,
            error.localizedDescription
        )
        return "liteweight could not read its iCloud backup folder. Check your connection and iCloud Drive, then try again."
    }
}

// MARK: - Create / Delete Backup
extension BackupFileStore {
    func delete(at index: Int) throws {
        guard index < backups.count else { return }
        try FileManager.default.removeItem(at: backups[index].url)
        backups.remove(at: index)
    }
    
    func create(
        data: @escaping () throws -> Data,
        onSuccess: @escaping (URL) -> Void = { _ in },
        onError: @escaping (Error) -> Void
    ) {
        Self.create(data: data) { result in
            switch result {
            case .success(let url):
                self.fetchBackups()
                onSuccess(url)
            case .failure(let error):
                onError(error)
            }
        }
    }
    
    // data in closure so it is computed on the background thread and only if necessary
    static func create(data: @escaping () throws -> Data, completion: @escaping (Result<URL, Error>) -> Void) {
        UbiquityContainer.backupsUrl { result in
            do {
                let backupsUrl = try result.get()
                let deviceName = UIDevice.current.name
                    .components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|").union(.illegalCharacters))
                    .joined(separator: "")
                    .components(separatedBy: .whitespacesAndNewlines)
                    .joined(separator: " ")
                var deviceBackupUrl = backupsUrl.appendingPathComponent(deviceName)
                
                if !FileManager.default.fileExists(atPath: deviceBackupUrl.path) {
                    do {
                        os_log("Creating device backup folder", log: .backup, type: .default)
                        try FileManager.default.createDirectory(at: deviceBackupUrl, withIntermediateDirectories: false)
                        os_log("Successfully created device backup folder", log: .backup, type: .info)
                    } catch {
                        os_log("Could not create device backup folder, falling back to creating folder for \"Unknown Device\"", log: .backup, type: .error)
                        deviceBackupUrl = backupsUrl.appendingPathComponent("Unknown Device")
                        if !FileManager.default.fileExists(atPath: deviceBackupUrl.path) {
                            try FileManager.default.createDirectory(at: deviceBackupUrl, withIntermediateDirectories: false)
                        }
                    }
                }
                
                let fileUrl = try writeBackup(data: data(), directory: deviceBackupUrl)
                
                completion(.success(fileUrl))
            } catch {
                os_log("Could not create backup: %@", log: .backup, type: .error, error.localizedDescription)
                completion(.failure(error))
            }
        }
    }

    static func writeBackup(data: Data, directory: URL, date: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileURL = directory.appendingPathComponent(formatter.string(from: date))
            .appendingPathExtension(LiteweightBackup.backupFilenameExtension)
        os_log("Saving backup to %@", log: .backup, type: .default, fileURL as NSURL)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

// MARK: - Misc
extension BackupFileStore {
    var lastBackup: BackupFile? {
        backups.first // assume backups are sorted
    }
}

// MARK: - Formatters
extension BackupFileStore.BackupFile {
    static let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.doesRelativeDateFormatting = true
        return dateFormatter
    }()
    
    static let byteCountFormatter: ByteCountFormatter = {
        ByteCountFormatter()
    }()
}

/// Captures Core Data on its owning queue before the asynchronous iCloud write.
/// Never block the main queue waiting for work that may need that same queue.
@MainActor
final class AutomaticBackupCoordinator {
    static let shared = AutomaticBackupCoordinator()

    typealias Writer = (Data, @escaping (Result<URL, Error>) -> Void) -> Void
    private let write: Writer
    private let begin: (@escaping () -> Void) -> UIBackgroundTaskIdentifier
    private let end: (UIBackgroundTaskIdentifier) -> Void
    private var runID: UUID?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init(
        write: @escaping Writer = { data, completion in
            BackupFileStore.create(data: { data }, completion: completion)
        },
        begin: @escaping (@escaping () -> Void) -> UIBackgroundTaskIdentifier = { expiration in
            UIApplication.shared.beginBackgroundTask(withName: "Automatic backup", expirationHandler: expiration)
        },
        end: @escaping (UIBackgroundTaskIdentifier) -> Void = { task in
            UIApplication.shared.endBackgroundTask(task)
        }
    ) {
        self.write = write
        self.begin = begin
        self.end = end
    }

    func start(makeData: () throws -> Data) {
        guard runID == nil else { return }
        let id = UUID()
        runID = id
        backgroundTask = begin { [weak self] in
            Task { @MainActor in self?.endBackgroundTime(id: id) }
        }
        do {
            let data = try makeData()
            write(data) { [weak self] result in
                Task { @MainActor in
                    if case .failure(let error) = result {
                        os_log("Auto backup failed: %@", log: .backup, type: .error, error.localizedDescription)
                    }
                    self?.finish(id: id)
                }
            }
        } catch {
            os_log("Could not capture auto backup: %@", log: .backup, type: .error, error.localizedDescription)
            finish(id: id)
        }
    }

    private func finish(id: UUID) {
        guard runID == id else { return }
        endBackgroundTime(id: id)
        runID = nil
    }

    private func endBackgroundTime(id: UUID) {
        guard runID == id else { return }
        // Expiration ends our background allowance, not the file operation.
        // Keep the run in flight until its callback so an older write cannot
        // race a newer snapshot to the same daily backup file.
        let task = backgroundTask
        backgroundTask = .invalid
        if task != .invalid { end(task) }
    }
}
