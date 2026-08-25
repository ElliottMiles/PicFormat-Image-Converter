//
//  FileExportService.swift
//  Good_Image_Converter
//

import Foundation

enum FileExportService {

    /// Sweeps every kind of leftover temp file this app can create: every
    /// Export-* export folder (unconditionally — a fresh process launch
    /// can't have anything genuinely in flight), and "-Inbox" folders
    /// left behind by UIDocumentPickerViewController's asCopy:true import
    /// mode (normally cleaned up per-file right after import, but this
    /// also catches anything from before that cleanup existed, or from a
    /// session that was killed mid-import). Meant to be called once at
    /// app launch.
    nonisolated static func cleanUpTemporaryDirectoryOnLaunch() {
        removeExportDirectories(onlyOlderThan: nil)
        removeInboxDirectories()
    }

    /// Deletes every Export-* folder unconditionally. Safe to call once
    /// the results screen has actually disappeared (not just been
    /// covered by a sheet) — at that point every Save/Share/Photos flow
    /// from that screen's lifetime, not just the most recent one, has
    /// necessarily already finished with its files.
    nonisolated static func removeAllExportDirectories() {
        removeExportDirectories(onlyOlderThan: nil)
    }

    nonisolated private static func removeInboxDirectories() {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        guard let contents = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) else {
            return
        }
        for url in contents where url.lastPathComponent.hasSuffix("-Inbox") {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Writes results out to a scratch directory under the app's own
    /// filenames so they can be handed to UIDocumentPickerViewController
    /// or UIActivityViewController with the right names already baked in.
    nonisolated static func writeTemporaryFiles(for results: [ConversionResult]) throws -> [URL] {
        removeStaleExportDirectories()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        return try results.map { result in
            let url = tempDir.appendingPathComponent(result.filename)
            try result.data.write(to: url, options: .atomic)
            return url
        }
    }

    /// Every Save/Share tap leaves a UUID-named export folder behind with
    /// nothing to clean it up on its own, so stale ones are swept here
    /// before a new one is created. Under normal operation there's no way
    /// for a currently-open export's files to still be in use when the
    /// next one starts (Save/Share are modal sheets, and this function is
    /// synchronous with no await point) — but only directories older than
    /// `staleExportAge` are removed here anyway, as cheap extra insurance
    /// against deleting something a still-open system picker or share
    /// sheet might reference, e.g. mid-flow while the user is creating a
    /// new folder to save into. This age gate is specific to this
    /// mid-session call site — `removeAllExportDirectories()` and the
    /// app-launch sweep both delete unconditionally, since at those two
    /// points nothing could legitimately still be using any of them.
    nonisolated private static let staleExportAge: TimeInterval = 10 * 60

    nonisolated private static func removeStaleExportDirectories() {
        removeExportDirectories(onlyOlderThan: staleExportAge)
    }

    /// `age` of `nil` deletes every Export-* folder unconditionally; a
    /// non-nil age skips (rather than guesses at) any folder whose
    /// creation date can't be determined, leaving it for a later sweep.
    nonisolated private static func removeExportDirectories(onlyOlderThan age: TimeInterval?) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        guard let contents = try? fileManager.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: age != nil ? [.creationDateKey] : nil
        ) else {
            return
        }

        let cutoff = age.map { Date().addingTimeInterval(-$0) }
        for url in contents where url.lastPathComponent.hasPrefix("Export-") {
            if let cutoff {
                guard let creationDate = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                      creationDate <= cutoff else {
                    continue
                }
            }
            try? fileManager.removeItem(at: url)
        }
    }

    /// Builds final on-disk filenames for a batch, keeping filenames
    /// stable and collision-free even if the user's base name repeats
    /// across a batch import.
    nonisolated static func filenames(baseName: String, count: Int, extension ext: String) -> [String] {
        let sanitized = sanitize(baseName)
        if count == 1 {
            return ["\(sanitized).\(ext)"]
        }
        return (1...count).map { "\(sanitized)-\($0).\(ext)" }
    }

    nonisolated static func sanitize(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = trimmed.components(separatedBy: invalidCharacters).joined(separator: "-")
        return cleaned.isEmpty ? "Converted Image" : cleaned
    }
}
