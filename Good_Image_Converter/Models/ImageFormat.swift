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
    case heif
    case tiff
    case gif
    case bmp
    case avif
    case webp
    case svg

    nonisolated var id: String { rawValue }

    /// The ImageIO/UTType identifier used to drive `CGImageDestination`.
    nonisolated var utType: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .heif: return .heif
        case .tiff: return .tiff
        case .gif: return .gif
        case .bmp: return .bmp
        case .avif: return UTType("public.avif") ?? .png
        case .webp: return UTType("org.webmproject.webp") ?? .png
        case .svg: return .svg
        }
    }

    nonisolated var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .heif: return "heif"
        case .tiff: return "tiff"
        case .gif: return "gif"
        case .bmp: return "bmp"
        case .avif: return "avif"
        case .webp: return "webp"
        case .svg: return "svg"
        }
    }

    nonisolated var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .heif: return "HEIF"
        case .tiff: return "TIFF"
        case .gif: return "GIF"
        case .bmp: return "BMP"
        case .avif: return "AVIF"
        case .webp: return "WebP"
        case .svg: return "SVG"
        }
    }

    nonisolated var shortDescription: String {
        switch self {
        case .jpeg: return "Universal, adjustable compression"
        case .png: return "Lossless, supports transparency"
        case .heic: return "Apple's efficient photo format"
        case .heif: return "High-efficiency image container"
        case .tiff: return "Lossless, large file size"
        case .gif: return "Lossless, limited to 256 colors"
        case .bmp: return "Uncompressed, very large files"
        case .avif: return "Next-gen format, small files"
        case .webp: return "Efficient web-friendly format"
        case .svg: return "Image embedded in a vector wrapper"
        }
    }

    /// Whether this format has a meaningful lossy/quality dial.
    nonisolated var supportsVariableQuality: Bool {
        switch self {
        case .jpeg, .heic, .heif, .avif, .webp: return true
        case .png, .tiff, .gif, .bmp, .svg: return false
        }
    }

    /// Whether this format supports an alpha channel.
    nonisolated var supportsTransparency: Bool {
        switch self {
        case .png, .gif, .bmp, .tiff, .avif, .webp, .heif: return true
        case .jpeg, .heic, .svg: return false
        }
    }
}
