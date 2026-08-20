//
//  ResultsView.swift
//  Good_Image_Converter
//

import SwiftUI

struct ResultsView: View {
    @Bindable var viewModel: ConverterViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                summaryCard
                resultsGrid
            }
            .padding()
        }
        .navigationTitle("Converted")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let message = viewModel.saveConfirmationMessage {
                    Text(message)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                }
                HStack(spacing: 12) {
                    Button {
                        viewModel.isPresentingSaveDestinationChooser = true
                    } label: {
                        if viewModel.isSavingToPhotos {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isSavingToPhotos)

                    Button {
                        if viewModel.prepareExportFiles() {
                            viewModel.isPresentingShareSheet = true
                        }
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding()
            .background(.bar)
        }
        .confirmationDialog("Save to…", isPresented: $viewModel.isPresentingSaveDestinationChooser, titleVisibility: .visible) {
            if viewModel.canSaveToPhotos {
                Button("Photos") {
                    Task { await viewModel.saveToPhotoLibrary() }
                }
            }
            Button("Files") {
                if viewModel.prepareExportFiles() {
                    viewModel.isPresentingSaveSheet = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $viewModel.isPresentingSaveSheet) {
            DocumentExporter(urls: viewModel.exportURLs) { success in
                viewModel.isPresentingSaveSheet = false
                viewModel.handleSaveCompletion(success: success)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $viewModel.isPresentingShareSheet) {
            ShareSheet(items: viewModel.exportURLs)
        }
    }

    private var summaryCard: some View {
        let saved = viewModel.totalOriginalBytes - viewModel.totalConvertedBytes
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(viewModel.conversionResults.count) image\(viewModel.conversionResults.count == 1 ? "" : "s") converted to \(viewModel.selectedFormat?.displayName ?? "")")
                .font(.headline)
            Text(ByteCountFormatter.string(fromByteCount: Int64(viewModel.totalConvertedBytes), countStyle: .file) + " total"
                 + (saved > 0 ? " · \(ByteCountFormatter.string(fromByteCount: Int64(saved), countStyle: .file)) smaller than originals" : ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var resultsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            ForEach(viewModel.conversionResults) { result in
                VStack(alignment: .leading, spacing: 6) {
                    Image(uiImage: result.thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 130)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(result.filename)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(result.formattedByteCount)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ResultsView(viewModel: ConverterViewModel())
    }
}
