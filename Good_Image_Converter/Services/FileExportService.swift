//
//  FileExportService.swift
//  Good_Image_Converter
//

import Foundation

enum FileExportService {

    /// Sweeps every kind of leftover temp file this app can create:
    /// stale Export-* export folders, and "-Inbox" folders left behind by
    /// UIDocumentPickerViewController's asCopy:true import mode (normally
    /// cleaned up per-file right after import, but this also catches
    /// anything from before that cleanup existed, or from a session that
    /// was killed mid-import). Meant to be called once at app launch,
    /// when nothing could possibly still be mid-flow yet.
    nonisolated static func cleanUpTemporaryDirectoryOnLaunch() {
        removeStaleExportDirectories()
        removeInboxDirectories()
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
    /// nothing to clean it up. Under normal operation there's no way for a
    /// currently-open export's files to still be in use when the next one
    /// starts (Save/Share are modal sheets, and this function is
    /// synchronous with no await point) — but only directories older than
    /// `staleExportAge` are removed anyway, as cheap extra insurance
    /// against deleting something a still-open system picker or share
    /// sheet might reference, e.g. mid-flow while the user is creating a
    /// new folder to save into. A directory whose age can't be determined
    /// is left alone rather than guessed at; it'll be swept on a later
    /// call once it's unambiguously old enough.
    nonisolated private static let staleExportAge: TimeInterval = 10 * 60

    nonisolated private static func removeStaleExportDirectories() {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        guard let contents = try? fileManager.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
            return
        }

        let cutoff = Date().addingTimeInterval(-staleExportAge)
        for url in contents where url.lastPathComponent.hasPrefix("Export-") {
            guard let creationDate = try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  creationDate <= cutoff else {
                continue
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
