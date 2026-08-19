//
//  ContentView.swift
//  Good_Image_Converter
//

import SwiftUI
import PhotosUI

private enum Stage: Hashable {
    case configure
    case results
}

struct ContentView: View {
    @State private var viewModel = ConverterViewModel()
    @State private var path: [Stage] = []

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isPresentingFilesImporter = false
    @State private var isPresentingCamera = false
    @State private var isLoadingImports = false

    var body: some View {
        NavigationStack(path: $path) {
            importStage
                .navigationTitle("Image Converter")
                .navigationDestination(for: Stage.self) { stage in
                    switch stage {
                    case .configure:
                        ConfigureView(viewModel: viewModel) {
                            path.append(.results)
                        }
                    case .results:
                        ResultsView(viewModel: viewModel)
                    }
                }
        }
    }

    // MARK: - Import stage

    private var importStage: some View {
        ScrollView {
            VStack(spacing: 24) {
                if !viewModel.hasImages {
                    EmptyImportState()
                        .padding(.top, 40)
                } else {
                    ImportedImageGrid(viewModel: viewModel)
                }

                importSourceButtons

                if !viewModel.importIssues.isEmpty {
                    IssuesBanner(title: "Some files couldn't be imported", messages: viewModel.importIssues) {
                        viewModel.importIssues.removeAll()
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.hasImages {
                Button {
                    path.append(.configure)
                } label: {
                    Text("Continue with \(viewModel.importedImages.count) \(viewModel.importedImages.count == 1 ? "Image" : "Images")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
        .overlay {
            if isLoadingImports {
                ProgressView("Importing…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .fullScreenCover(isPresented: $isPresentingCamera) {
            CameraCapture { image in
                isPresentingCamera = false
                guard let image else { return }
                Task.detached(priority: .userInitiated) {
                    let result = Result {
                        try ImageDecoder.decode(uiImage: image, suggestedName: "Photo \(Date().formatted(date: .numeric, time: .standard))")
                    }
                    await viewModel.addImage(result: result)
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isPresentingFilesImporter) {
            FilesImporter { urls in
                isPresentingFilesImporter = false
                guard !urls.isEmpty else { return }
                Task { await importFileURLs(urls) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photoSelection) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await importPhotoPickerItems(newItems)
                photoSelection = []
            }
        }
    }

    private var importSourceButtons: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $photoSelection, maxSelectionCount: viewModel.remainingImportCapacity, matching: .images) {
                SourceButtonLabel(systemImage: "photo.on.rectangle.angled", title: "Photo Library", subtitle: "Choose one or many photos")
            }

            Button {
                isPresentingFilesImporter = true
            } label: {
                SourceButtonLabel(systemImage: "folder", title: "Files", subtitle: "Import from Files or iCloud Drive")
            }

            Button {
                isPresentingCamera = true
            } label: {
                SourceButtonLabel(systemImage: "camera", title: "Camera", subtitle: "Take a new photo")
            }
        }
    }

    // MARK: - Import handling

    private func importPhotoPickerItems(_ items: [PhotosPickerItem]) async {
        isLoadingImports = true
        defer { isLoadingImports = false }

        var results: [Result<ImportedImage, Error>] = []
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    results.append(.failure(ImportError.unsupportedData))
                    continue
                }
                let name = item.itemIdentifier ?? "Photo"
                results.append(Result { try ImageDecoder.decode(data: data, suggestedName: name) })
            } catch {
                results.append(.failure(error))
            }
        }
        viewModel.addImages(results)
    }

    private func importFileURLs(_ urls: [URL]) async {
        isLoadingImports = true
        defer { isLoadingImports = false }

        let capacity = viewModel.remainingImportCapacity
        let admitted = Array(urls.prefix(capacity))
        if admitted.count < urls.count {
            viewModel.importIssues.append("Only imported \(admitted.count) of \(urls.count) — 25 image limit per batch")
        }
        guard !admitted.isEmpty else { return }

        // Task.detached specifically — see ConverterViewModel.convert()
        // for why a plain Task{} wouldn't actually leave the main actor
        // under this project's default actor isolation setting.
        let results = await Task.detached(priority: .userInitiated) {
            Self.decodeFileURLs(admitted)
        }.value

        viewModel.addImages(results)
    }

    nonisolated private static func decodeFileURLs(_ urls: [URL]) -> [Result<ImportedImage, Error>] {
        var results: [Result<ImportedImage, Error>] = []
        for url in urls {
            do {
                let data = try Data(contentsOf: url)
                results.append(Result { try ImageDecoder.decode(data: data, suggestedName: url.lastPathComponent) })
            } catch {
                results.append(.failure(ImportError.unreadableFile(name: url.lastPathComponent)))
            }
        }
        return results
    }
}

private struct SourceButtonLabel: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct EmptyImportState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.rays")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Convert Images")
                .font(.title2.bold())
            Text("Import photos from your library, Files, or the camera to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ImportedImageGrid: View {
    var viewModel: ConverterViewModel

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(viewModel.importedImages.count) Imported")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(viewModel.importedImages) { image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image.thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 92, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            viewModel.removeImage(image)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white, .black.opacity(0.6))
                        }
                        .padding(4)
                    }
                }
            }
        }
    }
}

struct IssuesBanner: View {
    let title: String
    let messages: [String]
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .font(.caption)
            }
            ForEach(messages, id: \.self) { message in
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ContentView()
}
