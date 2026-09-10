//
//  ConfigureView.swift
//  Good_Image_Converter
//

import SwiftUI

struct ConfigureView: View {
    @Bindable var viewModel: ConverterViewModel
    var onConverted: () -> Void

    @FocusState private var isFilenameFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                formatSection
                if viewModel.selectedFormat == .pdf && viewModel.isBatch {
                    pdfCombineSection
                }
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
        // Tapping any background/non-interactive area dismisses the
        // keyboard; buttons and other controls still get first crack at
        // their own taps, so this doesn't interfere with them.
        .onTapGesture {
            isFilenameFieldFocused = false
        }
        // Covers the "scroll down the page" case specifically — the
        // keyboard drops as soon as a scroll drag begins, before the tap
        // gesture above would ever get a chance to fire.
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Choose Format")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                isFilenameFieldFocused = false
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
                ForEach(ImageFormat.allCases) { format in
                    let isAvailable = FormatCapabilityService.isAvailable(format)
                    Button {
                        isFilenameFieldFocused = false
                        viewModel.selectedFormat = format
                    } label: {
                        FormatCard(format: format, isSelected: viewModel.selectedFormat == format, isAvailable: isAvailable)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isAvailable)
                }
            }
        }
    }

    private var pdfCombineSection: some View {
        let combineBinding = Binding(
            get: { viewModel.combinePDFPages },
            set: { newValue in
                isFilenameFieldFocused = false
                viewModel.combinePDFPages = newValue
            }
        )
        return Toggle(isOn: combineBinding) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Combine into One PDF")
                    .font(.subheadline.weight(.semibold))
                Text(viewModel.combinePDFPages
                     ? "All images become pages in a single PDF"
                     : "Each image becomes its own PDF")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quality")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(CompressionQuality.allCases) { quality in
                    QualityRow(quality: quality, isSelected: viewModel.selectedQuality == quality)
                        .onTapGesture {
                            isFilenameFieldFocused = false
                            viewModel.selectedQuality = quality
                        }
                }
            }
        }
    }

    private var filenameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.willProduceSingleFile ? "Filename" : "Filename Prefix")
                .font(.headline)

            TextField(viewModel.willProduceSingleFile ? "e.g. MyImage" : "e.g. Vacation", text: $viewModel.outputBaseName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($isFilenameFieldFocused)

            if let format = viewModel.selectedFormat {
                Text(viewModel.willProduceSingleFile
                     ? "Saved as \(FileExportService.sanitize(viewModel.outputBaseName)).\(format.fileExtension)"
                     : "Saved as \(FileExportService.sanitize(viewModel.outputBaseName))-1.\(format.fileExtension), -2.\(format.fileExtension), …")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct FormatCard: View {
    let format: ImageFormat
    let isSelected: Bool
    let isAvailable: Bool

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
            Text(isAvailable ? format.shortDescription : "Not available on this device")
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
        .opacity(isAvailable ? 1 : 0.4)
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
