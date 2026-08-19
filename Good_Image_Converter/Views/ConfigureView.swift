//
//  ConfigureView.swift
//  Good_Image_Converter
//

import SwiftUI

struct ConfigureView: View {
    @Bindable var viewModel: ConverterViewModel
    var onConverted: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                formatSection
                if viewModel.selectedFormat?.supportsVariableQuality == true {
                    qualitySection
                }
                filenameSection

                if !viewModel.conversionIssues.isEmpty {
                    IssuesBanner(title: "Some images couldn't be converted", messages: viewModel.conversionIssues) {
                        viewModel.conversionIssues.removeAll()
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Choose Format")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task {
                    await viewModel.convert()
                    if viewModel.hasResults {
                        onConverted()
                    }
                }
            } label: {
                if viewModel.isConverting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Convert \(viewModel.importedImages.count) \(viewModel.importedImages.count == 1 ? "Image" : "Images")")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.selectedFormat == nil || viewModel.isConverting)
            .padding()
            .background(.bar)
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Output Format")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(viewModel.availableFormats) { format in
                    FormatCard(format: format, isSelected: viewModel.selectedFormat == format)
                        .onTapGesture {
                            viewModel.selectedFormat = format
                        }
                }
            }
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quality")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(CompressionQuality.allCases) { quality in
                    QualityRow(quality: quality, isSelected: viewModel.selectedQuality == quality)
                        .onTapGesture {
                            viewModel.selectedQuality = quality
                        }
                }
            }
        }
    }

    private var filenameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.isBatch ? "Filename Prefix" : "Filename")
                .font(.headline)

            TextField(viewModel.isBatch ? "e.g. Vacation" : "e.g. MyImage", text: $viewModel.outputBaseName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            if let format = viewModel.selectedFormat {
                Text(viewModel.isBatch
                     ? "Saved as \(FileExportService.sanitize(viewModel.outputBaseName))-1.\(format.fileExtension), -2.\(format.fileExtension), …"
                     : "Saved as \(FileExportService.sanitize(viewModel.outputBaseName)).\(format.fileExtension)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FormatCard: View {
    let format: ImageFormat
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(format.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            Text(format.shortDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct QualityRow: View {
    let quality: CompressionQuality
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: quality.systemImageName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(quality.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(quality.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color(.tertiaryLabel))
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        ConfigureView(viewModel: ConverterViewModel()) {}
    }
}
