//
//  FileExportService.swift
//  Good_Image_Converter
//

import Foundation

enum FileExportService {

    /// Writes results out to a scratch directory under the app's own
    /// filenames so they can be handed to UIDocumentPickerViewController
    /// or UIActivityViewController with the right names already baked in.
    nonisolated static func writeTemporaryFiles(for results: [ConversionResult]) throws -> [URL] {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        return try results.map { result in
            let url = tempDir.appendingPathComponent(result.filename)
            try result.data.write(to: url, options: .atomic)
            return url
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
