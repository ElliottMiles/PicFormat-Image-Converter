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
    /// page per image. Unlike the single-image path, every page shares
    /// the same width — flipping through pages of wildly different sizes
    /// reads as broken, even though each page was individually correct —
    /// so each image is scaled (never cropped, never distorted) to a
    /// common width, with its height following proportionally. That
    /// shared width is the widest image in the batch, not an arbitrary
    /// constant or the first image: scaling every other page down to fit
    /// never has to upscale a lower-resolution image past its native
    /// detail, which scaling up to match a narrower image would risk.
    /// Used only when the user turns on "combine into one PDF" — the
    /// default per-image `convert(_:to:quality:)` path above already
    /// produces one single-page, page-size-equals-image-size PDF per
    /// image otherwise, where this kind of consistency isn't a concern.
    nonisolated static func convertCombinedPDF(images: [ImportedImage], quality: CompressionQuality) throws -> Data {
        let uprightImages = images.map { image in
            ImageOrientationNormalizer.normalize(image.cgImage, orientation: image.orientation)
        }
        let sharedWidth = uprightImages.map(\.width).max()

        let pages = try zip(images, uprightImages).map { image, upright in
            try makePDFPage(from: upright, quality: quality, sourceName: image.baseFilename, pageWidth: sharedWidth)
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

    /// One PDF page's worth of image data. `imageWidth`/`imageHeight` are
    /// the embedded JPEG's own native pixel dimensions (must match the
    /// actual encoded stream, or PDF readers misinterpret it).
    /// `pageWidth`/`pageHeight` are what's actually used for the page's
    /// own MediaBox and the content stream's paint-to-this-size matrix —
    /// in points, at the same 1 pixel = 1 pt scale used everywhere in
    /// this app — and are only different from the image's native size
    /// when a shared page width was requested (combined PDFs); the JPEG
    /// stream itself is never re-encoded to scale it, only the
    /// instruction for how large to paint it changes, exactly like
    /// resizing an <img> tag without touching the source file.
    private struct PDFPageImage {
        let imageWidth: Int
        let imageHeight: Int
        let pageWidth: Int
        let pageHeight: Int
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
    nonisolated private static func makePDFPage(from image: CGImage, quality: CompressionQuality, sourceName: String, pageWidth: Int? = nil) throws -> PDFPageImage {
        let jpegData = try encodeViaImageIO(image, format: .jpeg, quality: quality, sourceName: sourceName)
        let nativeWidth = image.width
        let nativeHeight = image.height

        let outputWidth: Int
        let outputHeight: Int
        if let pageWidth, nativeWidth > 0 {
            outputWidth = pageWidth
            let scaledHeight = Double(nativeHeight) * Double(pageWidth) / Double(nativeWidth)
            outputHeight = max(1, Int(scaledHeight.rounded()))
        } else {
            outputWidth = nativeWidth
            outputHeight = nativeHeight
        }

        return PDFPageImage(
            imageWidth: nativeWidth,
            imageHeight: nativeHeight,
            pageWidth: outputWidth,
            pageHeight: outputHeight,
            jpegData: jpegData
        )
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
                    + "/MediaBox [0 0 \(page.pageWidth) \(page.pageHeight)] "
                    + "/Resources << /XObject << /Im0 \(imageNumber) 0 R >> >> "
                    + "/Contents \(contentNumber) 0 R >>").data(using: .ascii)!)
            }

            writeObject(imageNumber) { data in
                data.append(("<< /Type /XObject /Subtype /Image /Width \(page.imageWidth) /Height \(page.imageHeight) "
                    + "/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode "
                    + "/Length \(page.jpegData.count) >>\nstream\n").data(using: .ascii)!)
                data.append(page.jpegData)
                data.append("\nendstream".data(using: .ascii)!)
            }

            writeObject(contentNumber) { data in
                // Image XObjects paint into the unit square by
                // convention; this scales that square up to exactly the
                // page's own width/height, so the image fills the page
                // edge to edge with no margin. Using pageWidth/pageHeight
                // here (rather than the JPEG's own native pixel size) is
                // what actually applies the shared-width scaling for
                // combined PDFs — the embedded JPEG bytes are untouched.
                let content = "q\n\(page.pageWidth) 0 0 \(page.pageHeight) 0 0 cm\n/Im0 Do\nQ"
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
