//
//  ImageFormat.swift
//  Good_Image_Converter
//
//  Output formats the app can produce. Availability is determined at
//  runtime by FormatCapabilityService — this enum only describes what a
//  format *is*, never whether the current device can actually produce it.
//

import UniformTypeIdentifiers

enum ImageFormat: String, CaseIterable, Identifiable, Hashable {
    case jpeg
    case png
    case heic
    case tiff
    case gif
    case bmp
    case svg

    nonisolated var id: String { rawValue }

    /// The ImageIO/UTType identifier used to drive `CGImageDestination`.
    nonisolated var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .tiff: return .tiff
        case .gif: return .gif
        case .bmp: return .bmp
        case .svg: return .svg
        }
    }

    nonisolated var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .tiff: return "tiff"
        case .gif: return "gif"
        case .bmp: return "bmp"
        case .svg: return "svg"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .gif: return "GIF"
        case .bmp: return "BMP"
        case .svg: return "SVG"
        }
    }

    nonisolated var shortDescription: String {
        switch self {
        case .jpeg: return "Universal, adjustable compression"
        case .png: return "Lossless, supports transparency"
        case .heic: return "Apple's efficient photo format"
        case .tiff: return "Lossless, large file size"
        case .gif: return "Lossless, limited to 256 colors"
        case .bmp: return "Uncompressed, very large files"
        case .svg: return "Image embedded in a vector wrapper"
        }
    }

    /// Whether this format has a meaningful lossy/quality dial.
    nonisolated var supportsVariableQuality: Bool {
        switch self {
        case .jpeg, .heic: return true
        case .png, .tiff, .gif, .bmp, .svg: return false
        }
    }

    /// Whether this format supports an alpha channel.
    nonisolated var supportsTransparency: Bool {
        switch self {
        case .png, .gif, .bmp, .tiff: return true
        case .jpeg, .heic, .svg: return false
        }
    }
}
