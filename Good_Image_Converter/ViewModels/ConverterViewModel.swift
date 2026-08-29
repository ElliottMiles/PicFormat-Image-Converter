//
//  ConverterViewModel.swift
//  Good_Image_Converter
//
//  Owns the whole import -> configure -> convert -> export flow.
//

import Foundation
import Observation

@Observable
@MainActor
final class ConverterViewModel {

    /// Cumulative cap across all sources — every ImportedImage keeps its
    /// full decoded CGImage in memory for the session, independent of
    /// thumbnail size, so this bounds the more fundamental memory cost.
    static let maxImportedImages = 25

    // Import
    private(set) var importedImages: [ImportedImage] = []
    var importIssues: [String] = []

    // Configuration
    let availableFormats: [ImageFormat] = FormatCapabilityService.availableFormats
    var selectedFormat: ImageFormat?
    var selectedQuality: CompressionQuality = .high
    var outputBaseName: String = "Converted"
    /// PDF-only, defaults off: combine every image into one multi-page
    /// PDF instead of one single-page PDF per image.
    var combinePDFPages = false

    // Conversion
    private(set) var conversionResults: [ConversionResult] = []
    var conversionIssues: [String] = []
    var isConverting = false

    // Export
    var isPresentingSaveDestinationChooser = false
    var isPresentingSaveSheet = false
    var isPresentingShareSheet = false
    var isSavingToPhotos = false
    var exportURLs: [URL] = []
    var saveConfirmationMessage: String?

    /// Neither of these is an image asset the Photos library can import:
    /// SVG output here is a raster image wrapped in an XML/vector
    /// container, and PDF is a document format, not a photo — so that
    /// destination isn't offered for either.
    var canSaveToPhotos: Bool {
        selectedFormat != .svg && selectedFormat != .pdf
    }

    init() {
        selectedFormat = availableFormats.first(where: { $0 == .jpeg }) ?? availableFormats.first
    }

    var hasImages: Bool { !importedImages.isEmpty }
    var hasResults: Bool { !conversionResults.isEmpty }
    var isBatch: Bool { importedImages.count > 1 }

    /// Whether the current configuration will produce exactly one output
    /// file regardless of how many images were imported — true for a
    /// single imported image, or for a batch being combined into one PDF.
    var willProduceSingleFile: Bool {
        !isBatch || (selectedFormat == .pdf && combinePDFPages)
    }

    /// How many more images can be admitted before hitting `maxImportedImages`.
    var remainingImportCapacity: Int {
        max(0, Self.maxImportedImages - importedImages.count)
    }

    var totalOriginalBytes: Int {
        importedImages.reduce(0) { $0 + $1.originalByteCount }
    }

    var totalConvertedBytes: Int {
        conversionResults.reduce(0) { $0 + $1.byteCount }
    }

    // MARK: - Import

    func addImage(_ image: ImportedImage) {
        guard importedImages.count < Self.maxImportedImages else { return }
        importedImages.append(image)
        syncOutputBaseNameIfNeeded()
    }

    func addImage(result: Result<ImportedImage, Error>) {
        switch result {
        case .success(let image):
            addImage(image)
        case .failure(let error):
            importIssues.append(error.localizedDescription)
        }
    }

    func addImages(_ results: [Result<ImportedImage, Error>]) {
        for result in results {
            addImage(result: result)
        }
    }

    func removeImage(_ image: ImportedImage) {
        importedImages.removeAll { $0.id == image.id }
        if importedImages.isEmpty {
            outputBaseName = "Converted"
        }
    }

    private func syncOutputBaseNameIfNeeded() {
        guard importedImages.count == 1, outputBaseName == "Converted" else { return }
        outputBaseName = importedImages[0].baseFilename
    }

    // MARK: - Conversion

    func convert() async {
        guard let format = selectedFormat, hasImages else { return }

        isConverting = true
        conversionIssues.removeAll()
        conversionResults.removeAll()

        let images = importedImages
        let quality = selectedQuality
        let combine = format == .pdf && combinePDFPages
        let filenames = FileExportService.filenames(
            baseName: outputBaseName,
            count: combine ? 1 : images.count,
            extension: format.fileExtension
        )

        // Task.detached specifically, not a plain Task{} — with
        // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, a plain Task created
        // from this MainActor method would still run on the main actor by
        // inheritance, which would silently defeat the point of this.
        // Kept sequential on purpose: encoding several HEIC images
        // concurrently would spike memory further, not help.
        let (results, issues) = await Task.detached(priority: .userInitiated) {
            Self.convertSequentially(images: images, filenames: filenames, format: format, quality: quality, combine: combine)
        }.value

        conversionResults = results
        conversionIssues = issues
        isConverting = false
    }

    nonisolated private static func convertSequentially(
        images: [ImportedImage],
        filenames: [String],
        format: ImageFormat,
        quality: CompressionQuality,
        combine: Bool
    ) -> (results: [ConversionResult], issues: [String]) {
        if combine, let firstImage = images.first, let combinedFilename = filenames.first {
            do {
                let data = try ImageConversionService.convertCombinedPDF(images: images, quality: quality)
                let result = ConversionResult(
                    sourceID: firstImage.id,
                    filename: combinedFilename,
                    data: data,
                    format: format,
                    thumbnail: firstImage.thumbnail
                )
                return ([result], [])
            } catch {
                return ([], [error.localizedDescription])
            }
        }

        var results: [ConversionResult] = []
        var issues: [String] = []

        for (image, filename) in zip(images, filenames) {
            do {
                let data = try ImageConversionService.convert(image, to: format, quality: quality)
                results.append(
                    ConversionResult(
                        sourceID: image.id,
                        filename: filename,
                        data: data,
                        format: format,
                        thumbnail: image.thumbnail
                    )
                )
            } catch {
                issues.append(error.localizedDescription)
            }
        }

        return (results, issues)
    }

    // MARK: - Export

    func prepareExportFiles() -> Bool {
        do {
            exportURLs = try FileExportService.writeTemporaryFiles(for: conversionResults)
            return true
        } catch {
            conversionIssues.append("Couldn't prepare files for export: \(error.localizedDescription)")
            return false
        }
    }

    func handleSaveCompletion(success: Bool) {
        if success {
            saveConfirmationMessage = conversionResults.count == 1
                ? "Saved \(conversionResults[0].filename)."
                : "Saved \(conversionResults.count) images."
        }
    }

    /// Deletes every export folder immediately — not just this session's
    /// most recent one (an earlier cancelled Save attempt before a later
    /// Share, for instance, would otherwise wait for the next export's
    /// stale-folder sweep or the next app launch). Safe to call
    /// unconditionally: by the time the results screen has actually
    /// disappeared (not just covered by a sheet), every Save/Share/Photos
    /// flow from this screen's lifetime has necessarily already finished
    /// with its files.
    func cleanUpExportFiles() {
        FileExportService.removeAllExportDirectories()
        exportURLs.removeAll()
    }

    func saveToPhotoLibrary() async {
        guard prepareExportFiles() else { return }

        isSavingToPhotos = true
        do {
            try await PhotoLibrarySaveService.save(urls: exportURLs)
            saveConfirmationMessage = conversionResults.count == 1
                ? "Saved \(conversionResults[0].filename) to Photos."
                : "Saved \(conversionResults.count) images to Photos."
        } catch {
            conversionIssues.append(error.localizedDescription)
        }
        isSavingToPhotos = false
    }
}
