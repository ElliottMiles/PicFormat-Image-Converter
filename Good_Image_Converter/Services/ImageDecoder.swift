//
//  ImageDecoder.swift
//  Good_Image_Converter
//
//  Turns raw image bytes (from Photos, Files, or the camera) into an
//  ImportedImage, reading the EXIF/TIFF orientation tag so downstream
//  conversion can normalize it correctly.
//

import ImageIO
import UIKit

enum ImageDecoder {

    nonisolated static func decode(data: Data, suggestedName: String) throws -> ImportedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ImportError.unreadableFile(name: suggestedName)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationValue = properties?[kCGImagePropertyOrientation] as? UInt32
        let orientation = orientationValue.flatMap(CGImagePropertyOrientation.init) ?? .up

        let baseName = baseFilename(from: suggestedName)
        let thumbnail = UIImage(cgImage: cgImage, scale: 1, orientation: uiOrientation(from: orientation))

        return ImportedImage(
            baseFilename: baseName,
            cgImage: cgImage,
            orientation: orientation,
            originalByteCount: data.count,
            thumbnail: thumbnail
        )
    }

    nonisolated static func decode(uiImage: UIImage, suggestedName: String) throws -> ImportedImage {
        guard let cgImage = uiImage.cgImage else {
            throw ImportError.unsupportedData
        }
        let orientation = cgOrientation(from: uiImage.imageOrientation)
        let thumbnail = UIImage(cgImage: cgImage, scale: 1, orientation: uiImage.imageOrientation)
        let estimatedBytes = uiImage.jpegData(compressionQuality: 1.0)?.count ?? 0

        return ImportedImage(
            baseFilename: baseFilename(from: suggestedName),
            cgImage: cgImage,
            orientation: orientation,
            originalByteCount: estimatedBytes,
            thumbnail: thumbnail
        )
    }

    nonisolated private static func baseFilename(from name: String) -> String {
        let stripped = (name as NSString).deletingPathExtension
        return stripped.isEmpty ? "Image" : stripped
    }

    /// No direct bridging initializer exists between these two orientation
    /// enums despite their identical case sets, so the mapping is manual.
    nonisolated private static func uiOrientation(from orientation: CGImagePropertyOrientation) -> UIImage.Orientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        }
    }

    nonisolated private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
