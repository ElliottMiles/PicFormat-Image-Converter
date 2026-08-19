//
//  ImageConversionService.swift
//  Good_Image_Converter
//
//  All actual image encoding funnels through here. Orientation is
//  normalized once up front so every downstream encoder (including ones
//  with no orientation-tag support, like BMP) gets pixels that are
//  already right-side up.
//

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageConversionService {

    nonisolated static func convert(_ image: ImportedImage, to format: ImageFormat, quality: CompressionQuality) throws -> Data {
        guard FormatCapabilityService.isAvailable(format) else {
            throw ConversionError.formatUnavailable(format)
        }

        let upright = ImageOrientationNormalizer.normalize(image.cgImage, orientation: image.orientation)

        switch format {
        case .svg:
            return try encodeSVG(upright, sourceName: image.baseFilename)
        case .webp:
            guard let data = WebPEncoder.encode(upright, quality: effectiveQuality(for: format, quality)) else {
                throw ConversionError.encodingFailed(name: image.baseFilename, format: format)
            }
            return data
        default:
            return try encodeViaImageIO(upright, format: format, quality: quality, sourceName: image.baseFilename)
        }
    }

    nonisolated private static func encodeViaImageIO(_ image: CGImage, format: ImageFormat, quality: CompressionQuality, sourceName: String) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.utType.identifier as CFString, 1, nil) else {
            throw ConversionError.encodingFailed(name: sourceName, format: format)
        }

        var properties: [CFString: Any] = [:]
        if format.supportsVariableQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = effectiveQuality(for: format, quality)
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.encodingFailed(name: sourceName, format: format)
        }

        return output as Data
    }

    /// Formats that are always lossless ignore the user's quality tier
    /// entirely; everything else passes the tier's encoder quality through.
    nonisolated private static func effectiveQuality(for format: ImageFormat, _ quality: CompressionQuality) -> CGFloat {
        format.supportsVariableQuality ? quality.encoderQuality : 1.0
    }

    /// SVG has no native raster encoder path on iOS. We wrap a lossless
    /// PNG rendition as a base64 data URI inside an <image> element, which
    /// is a flattened raster-in-SVG-container output, not true
    /// vectorization — there's no general way to vectorize an arbitrary
    /// photo. This is the same approach most consumer converters use for
    /// "export to SVG."
    nonisolated private static func encodeSVG(_ image: CGImage, sourceName: String) throws -> Data {
        let pngData = try encodeViaImageIO(image, format: .png, quality: .lossless, sourceName: sourceName)
        let base64 = pngData.base64EncodedString()
        let width = image.width
        let height = image.height
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(width)" height="\(height)" viewBox="0 0 \(width) \(height)">
        <image width="\(width)" height="\(height)" href="data:image/png;base64,\(base64)"/>
        </svg>
        """
        guard let data = svg.data(using: .utf8) else {
            throw ConversionError.encodingFailed(name: sourceName, format: .svg)
        }
        return data
    }
}
