//
//  PhotoLibrarySaveService.swift
//  Good_Image_Converter
//
//  Saves converted files into the user's Photos library as new assets.
//  Requests the "add-only" authorization level (backed by
//  NSPhotoLibraryAddUsageDescription) rather than full read/write access
//  — the app only ever appends new assets, it never browses or reads the
//  existing library.
//

import Foundation
import Photos

enum PhotoLibrarySaveError: LocalizedError {
    case permissionDenied
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Photos access was denied. Enable it in Settings to save images to your library."
        case .saveFailed(let reason):
            return "Couldn't save to Photos: \(reason)"
        }
    }
}

enum PhotoLibrarySaveService {

    /// Requests add-only Photos permission if needed, then saves every
    /// file at the given URLs into the user's library as new assets.
    nonisolated static func save(urls: [URL]) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PhotoLibrarySaveError.permissionDenied
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for url in urls {
                    PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
            }
        } catch {
            throw PhotoLibrarySaveError.saveFailed(error.localizedDescription)
        }
    }
}
