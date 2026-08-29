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
        case .pdf:
            let page = try makePDFPage(from: upright, quality: quality, sourceName: image.baseFilename)
            return buildPDF(pages: [page])
        default:
            return try encodeViaImageIO(upright, format: format, quality: quality, sourceName: image.baseFilename)
        }
    }

    /// Builds a single multi-page PDF from every image in the batch, one
    /// page per image, each page sized exactly to that image's own
    /// dimensions. Used only when the user turns on "combine into one
    /// PDF" — the default per-image `convert(_:to:quality:)` path above
    /// already produces one single-page PDF per image otherwise.
    nonisolated static func convertCombinedPDF(images: [ImportedImage], quality: CompressionQuality) throws -> Data {
        let pages = try images.map { image -> PDFPageImage in
            let upright = ImageOrientationNormalizer.normalize(image.cgImage, orientation: image.orientation)
            return try makePDFPage(from: upright, quality: quality, sourceName: image.baseFilename)
        }
        return buildPDF(pages: pages)
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

    // MARK: - PDF

    /// One PDF page's worth of image data: page/image dimensions in
    /// pixels (used directly as PDF points — 1 image pixel = 1 pt — so
    /// the page is always exactly the image's size, no separate paper
    /// size or margins) plus the already-JPEG-compressed bytes to embed.
    private struct PDFPageImage {
        let width: Int
        let height: Int
        let jpegData: Data
    }

    /// PDF pages here are always backed by a JPEG stream, at every
    /// quality tier including "Lossless" — this mirrors how this app's
    /// other lossy-capable formats (JPEG, HEIC) already treat their own
    /// "Lossless" tier as "the best this format's own encoder can do,"
    /// not a bit-exact guarantee. A genuinely pixel-lossless PDF page
    /// would need a hand-rolled zlib/Flate compressor for the image
    /// stream, which risks producing a corrupted, unreadable PDF if
    /// implemented even slightly wrong — a worse failure than "not
    /// literally bit-exact," and not verifiable here without a working
    /// build. JPEG via the already-proven encodeViaImageIO path is the
    /// safer choice.
    nonisolated private static func makePDFPage(from image: CGImage, quality: CompressionQuality, sourceName: String) throws -> PDFPageImage {
        let jpegData = try encodeViaImageIO(image, format: .jpeg, quality: quality, sourceName: sourceName)
        return PDFPageImage(width: image.width, height: image.height, jpegData: jpegData)
    }

    /// Hand-writes a minimal but spec-valid PDF (header, catalog, page
    /// tree, one Image XObject + content stream per page, xref table,
    /// trailer) rather than going through Core Graphics' own PDF context.
    /// CGContext's PDF drawing doesn't document whether it preserves an
    /// embedded image's existing JPEG compression or re-flattens it to a
    /// raw bitmap stream when you draw a CGImage into a page — if it does
    /// the latter, the compression quality tiers would have little or no
    /// effect on output size, silently defeating the point of offering
    /// them. Writing the `/Filter /DCTDecode` stream explicitly removes
    /// that uncertainty: the JPEG bytes are embedded verbatim, so quality
    /// controls file size exactly as it does for a plain .jpg export.
    nonisolated private static func buildPDF(pages: [PDFPageImage]) -> Data {
        let catalogNumber = 1
        let pagesNumber = 2
        var pageNumbers: [Int] = []
        var imageNumbers: [Int] = []
        var contentNumbers: [Int] = []
        var nextObjectNumber = 3
        for _ in pages {
            pageNumbers.append(nextObjectNumber); nextObjectNumber += 1
            imageNumbers.append(nextObjectNumber); nextObjectNumber += 1
            contentNumbers.append(nextObjectNumber); nextObjectNumber += 1
        }
        let objectCount = nextObjectNumber - 1

        var pdf = Data()
        var objectOffsets = [Int](repeating: 0, count: objectCount + 1)

        func writeObject(_ number: Int, _ body: (inout Data) -> Void) {
            objectOffsets[number] = pdf.count
            pdf.append("\(number) 0 obj\n".data(using: .ascii)!)
            body(&pdf)
            pdf.append("\nendobj\n".data(using: .ascii)!)
        }

        pdf.append("%PDF-1.4\n".data(using: .ascii)!)

        writeObject(catalogNumber) { data in
            data.append("<< /Type /Catalog /Pages \(pagesNumber) 0 R >>".data(using: .ascii)!)
        }

        writeObject(pagesNumber) { data in
            let kids = pageNumbers.map { "\($0) 0 R" }.joined(separator: " ")
            data.append("<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>".data(using: .ascii)!)
        }

        for (index, page) in pages.enumerated() {
            let pageNumber = pageNumbers[index]
            let imageNumber = imageNumbers[index]
            let contentNumber = contentNumbers[index]

            writeObject(pageNumber) { data in
                data.append(("<< /Type /Page /Parent \(pagesNumber) 0 R "
                    + "/MediaBox [0 0 \(page.width) \(page.height)] "
                    + "/Resources << /XObject << /Im0 \(imageNumber) 0 R >> >> "
                    + "/Contents \(contentNumber) 0 R >>").data(using: .ascii)!)
            }

            writeObject(imageNumber) { data in
                data.append(("<< /Type /XObject /Subtype /Image /Width \(page.width) /Height \(page.height) "
                    + "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode "
                    + "/Length \(page.jpegData.count) >>\nstream\n").data(using: .ascii)!)
                data.append(page.jpegData)
                data.append("\nendstream".data(using: .ascii)!)
            }

            writeObject(contentNumber) { data in
                // Image XObjects paint into the unit square by
                // convention; this scales that square up to exactly the
                // page's own width/height, so the image fills the page
                // edge to edge with no margin.
                let content = "q\n\(page.width) 0 0 \(page.height) 0 0 cm\n/Im0 Do\nQ"
                data.append("<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream".data(using: .ascii)!)
            }
        }

        let xrefOffset = pdf.count
        pdf.append("xref\n0 \(objectCount + 1)\n".data(using: .ascii)!)
        pdf.append("0000000000 65535 f \n".data(using: .ascii)!)
        // 1..<(objectCount + 1) rather than 1...objectCount: stays a
        // valid (empty) range if this is ever called with no pages,
        // instead of crashing on an invalid 1...0 bound.
        for number in 1..<(objectCount + 1) {
            let offset = String(format: "%010d", objectOffsets[number])
            pdf.append("\(offset) 00000 n \n".data(using: .ascii)!)
        }

        pdf.append(("trailer\n<< /Size \(objectCount + 1) /Root \(catalogNumber) 0 R >>\n"
            + "startxref\n\(xrefOffset)\n%%EOF").data(using: .ascii)!)

        return pdf
    }
}
