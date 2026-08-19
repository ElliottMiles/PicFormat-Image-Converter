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
        let thumbnail = makeThumbnail(cgImage: cgImage, orientation: orientation)

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
        let thumbnail = makeThumbnail(cgImage: cgImage, orientation: orientation)
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

    /// Builds an actual downsized thumbnail instead of handing grid cells
    /// the full-resolution decode — SwiftUI still rasterizes the full
    /// bitmap per cell otherwise, which scales badly with batch size and
    /// photo resolution.
    ///
    /// `UIImage.preparingThumbnail(of:)` is the primary path, but its
    /// output scale isn't blindly trusted — the same screen-scale-
    /// inflation trap `ImageOrientationNormalizer` avoids for
    /// `UIGraphicsImageRenderer` could in principle apply here too. The
    /// pixel dimensions it actually returns are checked against what a
    /// scale-1 result should look like, and if they're unexpectedly
    /// large (or the API returns nil), a manual scale-controlled
    /// CGContext draw is used instead. This check runs on every call
    /// rather than relying on a one-time manual test, since that also
    /// makes the fallback self-correcting across OS versions/devices.
    nonisolated private static func makeThumbnail(cgImage: CGImage, orientation: CGImagePropertyOrientation) -> UIImage {
        let fullSizeImage = UIImage(cgImage: cgImage, scale: 1, orientation: uiOrientation(from: orientation))

        let longSide: CGFloat = 400
        let size = fullSizeImage.size
        guard size.width > 0, size.height > 0 else { return fullSizeImage }

        let scaleFactor = min(1, longSide / max(size.width, size.height))
        let targetSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        guard targetSize.width >= 1, targetSize.height >= 1 else { return fullSizeImage }

        if let prepared = fullSizeImage.preparingThumbnail(of: targetSize) {
            let expectedMaxPixels = max(targetSize.width, targetSize.height) * 1.5
            let actualMaxPixels = max(prepared.size.width * prepared.scale, prepared.size.height * prepared.scale)
            if actualMaxPixels <= expectedMaxPixels {
                return prepared
            }
        }

        let upright = ImageOrientationNormalizer.normalize(cgImage, orientation: orientation)
        return drawThumbnail(from: upright, targetSize: targetSize) ?? fullSizeImage
    }

    /// Manual fallback: draws an already-upright CGImage into a canvas
    /// sized explicitly in pixels, matching the same CGContext-based
    /// approach ImageOrientationNormalizer uses to avoid implicit scale
    /// inflation.
    nonisolated private static func drawThumbnail(from cgImage: CGImage, targetSize: CGSize) -> UIImage? {
        let width = max(1, Int(targetSize.width.rounded()))
        let height = max(1, Int(targetSize.height.rounded()))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let resized = context.makeImage() else { return nil }
        return UIImage(cgImage: resized, scale: 1, orientation: .up)
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
