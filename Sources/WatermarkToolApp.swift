import SwiftUI
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision
import Foundation
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        EmbeddedOllamaManager.shared.stop()
    }
}

@main
struct WatermarkToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Watermark Tool") {
            ContentView()
                .frame(minWidth: 760, minHeight: 610)
        }
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @State private var model = WatermarkModel()
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                settings
                    .frame(width: 300)
                Divider()
                preview
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            model.acceptDrop(providers)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Watermark Tool")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Quality-first local batch for Nikon NEF — slow OK, Mac stays usable")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            Spacer()
            if model.isProcessing {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        ProgressView(value: model.progress)
                            .frame(width: 150)
                        Text("\(model.completedCount) of \(model.totalCount)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text("Processing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Cancel") { model.cancel() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                folderSection
                Divider()
                watermarkSection
                Divider()
                appearanceSection
                Divider()
                analysisSection
                Button {
                    model.process()
                } label: {
                    Label("Watermark Images", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canProcess)
            }
            .padding(22)
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Folders", systemImage: "folder")
            Button {
                model.chooseInputFolder()
            } label: {
                Label(model.inputFolderName ?? "Choose input folder", systemImage: "arrow.down.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            Button {
                model.chooseOutputFolder()
            } label: {
                Label(model.outputFolderName ?? "Choose output folder", systemImage: "arrow.up.doc")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)

            if let count = model.imageCount {
                Text("\(count) supported image\(count == 1 ? "" : "s") found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var watermarkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Watermark", systemImage: "textformat")
            TextField("Text to add", text: $model.text)
                .textFieldStyle(.roundedBorder)
            Picker("Font", selection: $model.fontName) {
                ForEach(model.availableFonts, id: \.self) { font in
                    Text(font)
                        .font(.custom(font, size: 15))
                        .tag(font)
                }
            }
            Picker("Corner", selection: $model.corner) {
                ForEach(WatermarkCorner.allCases) { corner in
                    Text(corner.label).tag(corner)
                }
            }
            Picker("Direction", selection: $model.direction) {
                ForEach(WatermarkDirection.allCases) { direction in
                    Text(direction.label).tag(direction)
                }
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Appearance", systemImage: "slider.horizontal.3")
            LabeledContent("Opacity") {
                HStack(spacing: 8) {
                    Slider(value: $model.opacity, in: 0.05...1)
                    Text("\(Int(model.opacity * 100))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
            LabeledContent("Height") {
                HStack(spacing: 8) {
                    Slider(value: $model.heightPercent, in: 1...30)
                    Text("\(Int(model.heightPercent))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
            Text("Watermark size as a percentage of each image’s original height.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Bottom offset") {
                HStack(spacing: 8) {
                    Slider(value: $model.bottomOffsetPercent, in: 0...50)
                    Text("\(Int(model.bottomOffsetPercent))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
            Text("Height above the bottom edge. Used for either bottom corner.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Quality first (slow, low system impact)", isOn: $model.qualityFirst)
            Text("Prefer best output over speed: ISO denoise, full AI analysis, larger VL model, background CPU/GPU priority so other Mac work stays responsive. Batches may take hours.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Auto-enhance image", isOn: $model.autoEnhance)
            Text("Measured local exposure, shadows, contrast, vibrance, and sharpening (bounded; originals untouched).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("AI subject enhancement", isOn: $model.aiSubjectEnhance)
            Text("Vision finds the subject; the same bounded plan is applied only there with a soft feathered mask.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("JPEG quality") {
                HStack(spacing: 8) {
                    Slider(value: $model.jpegQuality, in: 0.5...1)
                    Text("\(Int(model.jpegQuality * 100))%")
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
            Picker("Output", selection: $model.outputFormat) {
                ForEach(OutputFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }
            if model.outputFormat == .original, model.containsRawInput {
                Text("Original format is not available for RAW files. Choose Compressed JPEG for NEF output.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Local analysis", systemImage: "cpu")
            Picker("AI analysis", selection: $model.analysisMode) {
                ForEach(AnalysisMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Text("Local Ollama classifies scene/lighting and softly biases the measured plan—no cloud calls, no free-form edits.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.analysisMode != .off {
                TextField("Local VL model tag", text: $model.ollamaModel)
                    .textFieldStyle(.roundedBorder)
                Text("Quality default: qwen3-vl:8b-instruct (falls back to 4b if missing). Instruct only—avoid thinking variants. Invalid JSON falls back to measured edits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Test local AI") { model.testLocalAI() }
                        .disabled(model.isTestingAI)
                    if model.isTestingAI {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                if let status = model.aiStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(model.aiIsAvailable ? .green : .orange)
                }
            }
            Divider()
            sectionTitle("Work log", systemImage: "list.bullet.rectangle")
            if model.logEntries.isEmpty {
                Text("Processing and AI decisions will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(model.logEntries.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 130)
            }
            if let logURL = model.logURL {
                Button("Show log in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([logURL])
                }
                .buttonStyle(.link)
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 18) {
            if let image = model.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(30)
                    .overlay(alignment: model.corner.alignment) {
                        if !model.text.isEmpty {
                            Text(model.text)
                                .font(.custom(model.fontName, size: model.previewFontSize))
                                .foregroundStyle(.white.opacity(model.opacity))
                                .shadow(color: .black.opacity(model.opacity * 0.65), radius: 0, x: 0, y: 0)
                                .rotationEffect(.radians(model.direction.angle))
                                .padding(30)
                                .offset(y: model.previewVerticalOffset)
                        }
                    }
            } else {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Text(isTargeted ? "Drop a folder or image here" : "Choose an input folder to preview its first image")
                    .foregroundStyle(.secondary)
            }
            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(model.didSucceed ? .green : .secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.04))
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
    }
}

enum WatermarkCorner: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }
    var label: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}

enum WatermarkDirection: String, CaseIterable, Identifiable {
    case normal, clockwise, upsideDown, counterclockwise

    var id: String { rawValue }
    var label: String {
        switch self {
        case .normal: "Normal"
        case .clockwise: "90° clockwise"
        case .upsideDown: "180°"
        case .counterclockwise: "90° counterclockwise"
        }
    }

    var angle: CGFloat {
        switch self {
        case .normal: 0
        case .clockwise: -.pi / 2
        case .upsideDown: .pi
        case .counterclockwise: .pi / 2
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case original, jpeg

    var id: String { rawValue }
    var label: String {
        switch self {
        case .original: "Original format"
        case .jpeg: "Compressed JPEG"
        }
    }
}

enum AnalysisMode: String, CaseIterable, Identifiable, Sendable {
    case off, selective, all

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .selective: "Selective (default)"
        case .all: "All images"
        }
    }
}

@MainActor
@Observable
final class WatermarkModel {
    var text = ""
    var fontName = "Helvetica Neue"
    var corner = WatermarkCorner.bottomRight
    var direction = WatermarkDirection.normal
    var opacity = 0.72
    var heightPercent = 5.0
    var bottomOffsetPercent = 2.5
    var jpegQuality = 0.95
    var outputFormat = OutputFormat.jpeg
    var autoEnhance = true
    var aiSubjectEnhance = true
    var qualityFirst = true
    var analysisMode = AnalysisMode.all
    var ollamaModel = EmbeddedOllamaManager.preferredModel
    var inputFolder: URL?
    var outputFolder: URL?
    var previewImage: NSImage?
    var imageCount: Int?
    var isProcessing = false
    var completedCount = 0
    var totalCount = 0
    var message: String?
    var didSucceed = false
    var logEntries: [String] = []
    var logURL: URL?
    var aiStatus: String?
    var aiIsAvailable = false
    var isTestingAI = false
    private var cancellationToken: RenderCancellationToken?

    var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    var containsRawInput: Bool {
        guard let inputFolder else { return false }
        return imageFiles(in: inputFolder).contains { isRaw($0) }
    }

    var previewFontSize: CGFloat {
        max(12, min(72, 420 * heightPercent / 100))
    }

    var previewVerticalOffset: CGFloat {
        switch corner {
        case .bottomLeft, .bottomRight:
            -CGFloat(420 * bottomOffsetPercent / 100)
        case .topLeft, .topRight:
            0
        }
    }

    let availableFonts = [
        "Helvetica Neue", "Avenir Next", "Georgia", "Menlo", "Futura", "Palatino",
        "Bradley Hand", "Chalkboard", "Marker Felt", "Noteworthy", "Apple Chancery",
        "Snell Roundhand", "SignPainter", "Zapfino"
    ]
    private let supportedExtensions = Set(["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif", "dng", "raw", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"])

    var inputFolderName: String? { inputFolder?.lastPathComponent }
    var outputFolderName: String? { outputFolder?.lastPathComponent }
    var canProcess: Bool {
        inputFolder != nil && outputFolder != nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isProcessing && !(outputFormat == .original && containsRawInput)
    }

    func chooseInputFolder() {
        guard let folder = chooseFolder() else { return }
        inputFolder = folder
        let files = imageFiles(in: folder)
        imageCount = files.count
        previewImage = files.first.flatMap { NSImage(contentsOf: $0) }
        message = nil
    }

    func chooseOutputFolder() {
        outputFolder = chooseFolder()
    }

    func testLocalAI() {
        isTestingAI = true
        aiStatus = "Starting bundled local AI…"
        LocalAIAnalyzer.testConnection(model: ollamaModel) { result in
            DispatchQueue.main.async {
                self.isTestingAI = false
                switch result {
                case .success(let message):
                    self.aiIsAvailable = true
                    self.aiStatus = message
                case .failure(let error):
                    self.aiIsAvailable = false
                    self.aiStatus = error.localizedDescription
                }
            }
        }
    }

    func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    self.inputFolder = url
                    self.imageCount = self.imageFiles(in: url).count
                    self.previewImage = self.imageFiles(in: url).first.flatMap { NSImage(contentsOf: $0) }
                }
            }
        }
        return true
    }

    func process() {
        guard let inputFolder, let outputFolder else { return }
        let files = imageFiles(in: inputFolder)
        isProcessing = true
        completedCount = 0
        totalCount = files.count
        message = nil
        didSucceed = false
        let cancellationToken = RenderCancellationToken()
        self.cancellationToken = cancellationToken
        let statusStore = RenderStatusStore(folder: outputFolder)
        let workLog = WorkLog(folder: outputFolder) { entries in
            DispatchQueue.main.async {
                self.logEntries = entries
            }
        }
        logURL = workLog.url
        logEntries = []
        let settings = RenderSettings(text: text, fontName: fontName, corner: corner, direction: direction, opacity: opacity, heightPercent: heightPercent, bottomOffsetPercent: bottomOffsetPercent, jpegQuality: jpegQuality, outputFormat: outputFormat, autoEnhance: autoEnhance, aiSubjectEnhance: aiSubjectEnhance, qualityFirst: qualityFirst, analysisMode: analysisMode, ollamaModel: ollamaModel)
        let queue = DispatchQueue.global(qos: settings.qualityFirst ? .utility : .userInitiated)
        queue.async {
            if settings.qualityFirst {
                // Leave interactive Mac work responsive while this batch runs for hours.
                Thread.current.qualityOfService = .utility
            }
            var completed = 0
            var failures = 0
            workLog.add("Batch started: \(files.count) image(s), qualityFirst=\(settings.qualityFirst), AI \(settings.analysisMode.label), model \(settings.ollamaModel)")
            for file in files {
                if cancellationToken.isCancelled { break }
                do {
                    if statusStore.isComplete(file: file, settings: settings) {
                        workLog.add("\(file.lastPathComponent): skipped (already complete)")
                        completed += 1
                    } else {
                        workLog.add("\(file.lastPathComponent): processing")
                        let outputURL = try ImageRenderer.render(file: file, to: outputFolder, settings: settings, log: workLog)
                        statusStore.markComplete(file: file, settings: settings, output: outputURL)
                        workLog.add("\(file.lastPathComponent): saved as \(outputURL.lastPathComponent)")
                        completed += 1
                    }
                } catch {
                    workLog.add("\(file.lastPathComponent): FAILED — \(error.localizedDescription)")
                    failures += 1
                }
                let processed = completed + failures
                DispatchQueue.main.async {
                    self.completedCount = processed
                }
            }
            workLog.add(cancellationToken.isCancelled ? "Batch cancelled" : "Batch finished: \(completed) completed, \(failures) failed")
            DispatchQueue.main.async {
                self.isProcessing = false
                self.cancellationToken = nil
                self.didSucceed = failures == 0 && !cancellationToken.isCancelled
                self.message = cancellationToken.isCancelled ? "Cancelled after \(completed) image\(completed == 1 ? "" : "s"). Resume is available." : failures == 0 ? "Created \(completed) watermarked image\(completed == 1 ? "" : "s") in the output folder." : "Created \(completed) image\(completed == 1 ? "" : "s"); \(failures) could not be processed."
            }
        }
    }

    func cancel() {
        cancellationToken?.cancel()
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func imageFiles(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.filter {
            supportedExtensions.contains($0.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? []
    }

    private func isRaw(_ file: URL) -> Bool {
        ["dng", "raw", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"].contains(file.pathExtension.lowercased())
    }
}

struct RenderSettings: Sendable {
    let text: String
    let fontName: String
    let corner: WatermarkCorner
    let direction: WatermarkDirection
    let opacity: Double
    let heightPercent: Double
    let bottomOffsetPercent: Double
    let jpegQuality: Double
    let outputFormat: OutputFormat
    let autoEnhance: Bool
    let aiSubjectEnhance: Bool
    let qualityFirst: Bool
    let analysisMode: AnalysisMode
    let ollamaModel: String
}

final class RenderCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

enum SceneCategory: String, Codable, CaseIterable, Sendable {
    case portrait, event, landscape, indoor, stage, street, unknown
}

enum LightingCategory: String, Codable, CaseIterable, Sendable {
    case daylight, overcast, indoor, stage, mixed, lowLight, unknown
}

enum RecommendedTreatment: String, Codable, CaseIterable, Sendable {
    case minimal, globalExposure = "global_exposure", shadowLift = "shadow_lift"
    case subjectLift = "subject_lift", preserveStageLighting = "preserve_stage_lighting", review
}

struct SceneAnalysis: Codable, Sendable {
    let sceneCategory: SceneCategory
    let lightingCategory: LightingCategory
    let subjectsUnderexposed: Bool
    let highlightsNeedProtection: Bool
    let preserveColoredLighting: Bool
    let recommendedTreatment: RecommendedTreatment
}

struct ImageMetrics: Sendable {
    let luminanceP20: Double
    let luminanceP50: Double
    let luminanceP99: Double
    let shadowFraction: Double
    let highlightHeadroom: Double
    let clippedChannelFraction: Double
}

struct EnhancementPlan: Sendable {
    let exposureStops: Double
    let shadowLift: Double
    let highlightAmount: Double
    let contrastAmount: Double
    let vibranceAmount: Double
    let sharpenAmount: Double
    let protectHighlights: Bool
    let preserveColor: Bool
    let review: Bool

    static let identity = EnhancementPlan(
        exposureStops: 0,
        shadowLift: 0,
        highlightAmount: 0,
        contrastAmount: 0,
        vibranceAmount: 0,
        sharpenAmount: 0,
        protectHighlights: false,
        preserveColor: false,
        review: false
    )

    func scaled(by factor: Double) -> EnhancementPlan {
        EnhancementPlan(
            exposureStops: exposureStops * factor,
            shadowLift: shadowLift * factor,
            highlightAmount: highlightAmount * factor,
            contrastAmount: contrastAmount * factor,
            vibranceAmount: vibranceAmount * factor,
            sharpenAmount: sharpenAmount * factor,
            protectHighlights: protectHighlights,
            preserveColor: preserveColor,
            review: review
        )
    }

    /// Second-pass subject boost for people: lift tone only — no extra vibrance/sharpen on skin.
    func skinSafeSubjectBoost(factor: Double) -> EnhancementPlan {
        EnhancementPlan(
            exposureStops: exposureStops * factor,
            shadowLift: shadowLift * factor,
            highlightAmount: highlightAmount * factor,
            contrastAmount: contrastAmount * factor * 0.35,
            vibranceAmount: 0,
            sharpenAmount: 0,
            protectHighlights: protectHighlights,
            preserveColor: true,
            review: review
        )
    }

    var hasAdjustments: Bool {
        exposureStops > 0.001 || shadowLift > 0.001 || highlightAmount > 0.001
            || contrastAmount > 0.001 || vibranceAmount > 0.001 || sharpenAmount > 0.001
    }
}

final class WorkLog: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var entries: [String] = []
    private let onChange: @Sendable ([String]) -> Void

    init(folder: URL, onChange: @escaping @Sendable ([String]) -> Void) {
        url = folder.appendingPathComponent("watermark-work.log")
        self.onChange = onChange
    }

    func add(_ message: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let line = "[\(formatter.string(from: Date()))] \(message)"
        lock.lock()
        entries.append(line)
        if entries.count > 200 {
            entries.removeFirst(entries.count - 200)
        }
        let snapshot = entries
        if let data = (line + "\n").data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                do {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                } catch {
                    // The in-app log remains available if the persistent log cannot be written.
                }
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
        lock.unlock()
        onChange(snapshot)
    }
}

final class EmbeddedOllamaManager: @unchecked Sendable {
    static let shared = EmbeddedOllamaManager()
    /// Quality-first default for M1 32GB personal use. Falls back to 4b if not staged.
    static let preferredModel = "qwen3-vl:8b-instruct"
    static let fallbackModel = "qwen3-vl:4b-instruct"
    static let knownModels = [preferredModel, fallbackModel]
    static let bundledModel = preferredModel
    static let baseURL = URL(string: "http://127.0.0.1:11435")!

    private let lock = NSLock()
    private var process: Process?
    private var runtimeLogHandle: FileHandle?
    private var requiredModelName = preferredModel

    private init() {}

    var runtimeLogURL: URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return applicationSupport
            .appendingPathComponent("WatermarkTool", isDirectory: true)
            .appendingPathComponent("embedded-ollama.log")
    }

    func ensureRunning(timeout: TimeInterval = 90, requiredModel: String? = nil, log: WorkLog? = nil) -> Result<URL, Error> {
        lock.lock()
        defer { lock.unlock() }

        if let requiredModel, !requiredModel.isEmpty {
            requiredModelName = requiredModel
        }

        if process?.isRunning == true, isHealthy(requiredModel: requiredModelName) {
            return .success(Self.baseURL)
        }

        stopLocked()
        guard let executable = bundledExecutableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            let error = LocalAIError.runtimeMissing
            log?.add("Bundled AI failed to start — \(error.localizedDescription)")
            return .failure(error)
        }
        guard let models = bundledModelsURL,
              FileManager.default.fileExists(atPath: models.path) else {
            let error = LocalAIError.bundledModelMissing
            log?.add("Bundled AI failed to start — \(error.localizedDescription)")
            return .failure(error)
        }

        do {
            try prepareRuntimeLog()
            let process = Process()
            process.executableURL = executable
            process.arguments = ["serve"]
            process.currentDirectoryURL = executable.deletingLastPathComponent()
            process.qualityOfService = .background
            var environment = ProcessInfo.processInfo.environment
            environment["OLLAMA_HOST"] = "127.0.0.1:11435"
            environment["OLLAMA_MODELS"] = models.path
            environment["OLLAMA_KEEP_ALIVE"] = "60m"
            environment["OLLAMA_NUM_PARALLEL"] = "1"
            environment["OLLAMA_MAX_LOADED_MODELS"] = "1"
            // Leave roughly half the cores free for other Mac work during long batches.
            let cores = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
            environment["OLLAMA_NUM_THREAD"] = String(cores)
            process.environment = environment
            process.standardOutput = runtimeLogHandle
            process.standardError = runtimeLogHandle
            try process.run()
            self.process = process
            setpriority(PRIO_PROCESS, Int32(process.processIdentifier), 15)
            log?.add("Bundled AI runtime started (PID \(process.processIdentifier), background QoS, \(cores) threads); runtime log: \(runtimeLogURL.path)")
        } catch {
            stopLocked()
            let wrapped = LocalAIError.runtimeStartFailed(error.localizedDescription)
            log?.add("Bundled AI failed to start — \(wrapped.localizedDescription)")
            return .failure(wrapped)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if process?.isRunning != true {
                let error = LocalAIError.runtimeExited
                log?.add("Bundled AI stopped during startup; see \(runtimeLogURL.path)")
                stopLocked()
                return .failure(error)
            }
            if isHealthy(requiredModel: requiredModelName) {
                log?.add("Bundled AI is ready on private localhost port 11435 (model \(resolvedAvailableModel(preferred: requiredModelName) ?? requiredModelName))")
                return .success(Self.baseURL)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        let error = LocalAIError.runtimeTimedOut
        log?.add("Bundled AI startup timed out; see \(runtimeLogURL.path)")
        stopLocked()
        return .failure(error)
    }

    func stop() {
        lock.lock()
        stopLocked()
        lock.unlock()
    }

    /// Prefer the requested tag; otherwise first known instruct model present in the bundle.
    func resolvedAvailableModel(preferred: String) -> String? {
        guard let tags = fetchTags() else { return nil }
        let names = Set(tags.models.map(\.name))
        if names.contains(preferred) { return preferred }
        for candidate in Self.knownModels where names.contains(candidate) {
            return candidate
        }
        return tags.models.first?.name
    }

    private var bundledExecutableURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("ollama")
    }

    private var bundledModelsURL: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Models", isDirectory: true)
    }

    private func isHealthy(requiredModel: String) -> Bool {
        resolvedAvailableModel(preferred: requiredModel) != nil
    }

    private func fetchTags() -> OllamaTagsResponse? {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        let semaphore = DispatchSemaphore(value: 0)
        let box = SynchronousDataBox()
        URLSession.shared.dataTask(with: request) { data, response, error in
            box.store(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode, error: error)
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + 2) == .success,
              box.error == nil, box.statusCode == 200, let data = box.data,
              let tags = try? JSONDecoder().decode(OllamaTagsResponse.self, from: data) else {
            return nil
        }
        return tags
    }

    private func prepareRuntimeLog() throws {
        let folder = runtimeLogURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: runtimeLogURL.path) {
            FileManager.default.createFile(atPath: runtimeLogURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: runtimeLogURL)
        try handle.seekToEnd()
        runtimeLogHandle = handle
    }

    private func stopLocked() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        try? runtimeLogHandle?.close()
        runtimeLogHandle = nil
    }
}

enum LocalAIAnalyzer {
    static let promptVersion = "scene-analysis-v3-quality"

    static func testConnection(model: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            switch EmbeddedOllamaManager.shared.ensureRunning(timeout: 120, requiredModel: model) {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                let resolved = EmbeddedOllamaManager.shared.resolvedAvailableModel(preferred: model) ?? model
                completion(.success("Bundled local AI is ready: \(resolved)."))
            }
        }
    }

    static func analyze(image: CGImage, file: URL, settings: RenderSettings, outputFolder: URL, metrics: ImageMetrics, log: WorkLog) -> SceneAnalysis? {
        guard settings.analysisMode != .off else {
            log.add("\(file.lastPathComponent): AI skipped (disabled)")
            return nil
        }
        let difficult = metrics.luminanceP50 < 0.22 || metrics.highlightHeadroom < 0.06 || metrics.shadowFraction > 0.45
        guard settings.analysisMode == .all || difficult else {
            log.add("\(file.lastPathComponent): AI skipped (selective mode; measurements not difficult)")
            return nil
        }
        let cache = AnalysisCache(folder: outputFolder)
        let key = cacheKey(file: file, settings: settings)
        if let cached = cache.value(for: key) {
            log.add("\(file.lastPathComponent): AI cache hit — \(cached.sceneCategory.rawValue), \(cached.recommendedTreatment.rawValue)")
            return cached
        }
        let previewMax = settings.qualityFirst ? 1536.0 : 1024.0
        guard let preview = previewJPEG(image, maxDimension: previewMax) else {
            log.add("\(file.lastPathComponent): AI fallback (could not create preview)")
            return nil
        }
        let preferredModel = settings.ollamaModel.isEmpty ? EmbeddedOllamaManager.preferredModel : settings.ollamaModel
        let startupTimeout: TimeInterval = settings.qualityFirst ? 180 : 90
        let baseURL: URL
        switch EmbeddedOllamaManager.shared.ensureRunning(timeout: startupTimeout, requiredModel: preferredModel, log: log) {
        case .success(let url):
            baseURL = url
        case .failure(let error):
            log.add("\(file.lastPathComponent): AI unavailable — \(error.localizedDescription); using measurement-only fallback")
            return nil
        }
        let model = EmbeddedOllamaManager.shared.resolvedAvailableModel(preferred: preferredModel) ?? preferredModel
        if model != preferredModel {
            log.add("\(file.lastPathComponent): requested model \(preferredModel) missing; using \(model)")
        }
        let request = OllamaRequest(
            model: model,
            prompt: "Classify this consistently developed event photograph (Nikon Z6 style). Return only the requested JSON. Do not suggest pixel masks or numeric edits.",
            images: [preview.base64EncodedString()],
            stream: false,
            format: schema,
            options: ["temperature": 0.0, "top_p": 0.1, "seed": 17, "num_predict": 200],
            keepAlive: settings.qualityFirst ? "60m" : "10m"
        )
        guard let body = try? JSONEncoder().encode(request) else {
            log.add("\(file.lastPathComponent): AI fallback (request encoding failed)")
            return nil
        }
        let endpoint = baseURL.appendingPathComponent("api/generate")
        let attemptTimeout: TimeInterval = settings.qualityFirst ? 600 : 180
        let attempts = settings.qualityFirst ? 3 : 2
        for attempt in 1...attempts {
            log.add("\(file.lastPathComponent): asking local AI \(model) (attempt \(attempt)/\(attempts), timeout \(Int(attemptTimeout))s)")
            var urlRequest = URLRequest(url: endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = attemptTimeout
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = body
            let semaphore = DispatchSemaphore(value: 0)
            let responseBox = SynchronousDataBox()
            URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                responseBox.store(data: data, statusCode: (response as? HTTPURLResponse)?.statusCode, error: error)
                semaphore.signal()
            }.resume()
            guard semaphore.wait(timeout: .now() + attemptTimeout + 1) == .success else {
                log.add("\(file.lastPathComponent): AI attempt \(attempt) timed out")
                continue
            }
            if let error = responseBox.error {
                log.add("\(file.lastPathComponent): AI attempt \(attempt) failed — \(error.localizedDescription)")
                continue
            }
            guard responseBox.statusCode == 200 else {
                log.add("\(file.lastPathComponent): AI attempt \(attempt) returned HTTP \(responseBox.statusCode ?? 0)")
                continue
            }
            if let responseData = responseBox.data,
               let response = try? JSONDecoder().decode(OllamaResponse.self, from: responseData),
               let result = try? JSONDecoder().decode(SceneAnalysis.self, from: Data(response.response.utf8)) {
                cache.store(result, for: key)
                log.add("\(file.lastPathComponent): AI succeeded — \(result.sceneCategory.rawValue), \(result.lightingCategory.rawValue), \(result.recommendedTreatment.rawValue)")
                return result
            }
            log.add("\(file.lastPathComponent): AI attempt \(attempt) returned invalid JSON")
        }
        log.add("\(file.lastPathComponent): AI unavailable; using measurement-only fallback")
        return nil
    }

    private static let schema: [String: AnyCodable] = [
        "type": AnyCodable("object"),
        "properties": AnyCodable([
            "sceneCategory": ["type": "string", "enum": SceneCategory.allCases.map(\.rawValue)],
            "lightingCategory": ["type": "string", "enum": LightingCategory.allCases.map(\.rawValue)],
            "subjectsUnderexposed": ["type": "boolean"],
            "highlightsNeedProtection": ["type": "boolean"],
            "preserveColoredLighting": ["type": "boolean"],
            "recommendedTreatment": ["type": "string", "enum": RecommendedTreatment.allCases.map(\.rawValue)]
        ]),
        "required": AnyCodable(["sceneCategory", "lightingCategory", "subjectsUnderexposed", "highlightsNeedProtection", "preserveColoredLighting", "recommendedTreatment"]),
        "additionalProperties": AnyCodable(false)
    ]

    private static func previewJPEG(_ image: CGImage, maxDimension: Double = 1024) -> Data? {
        let scale = min(1, maxDimension / Double(max(image.width, image.height)))
        let ciImage = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let preview = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, preview, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func cacheKey(file: URL, settings: RenderSettings) -> String {
        let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return [file.path, String(values?.fileSize ?? 0), String(describing: values?.contentModificationDate ?? .distantPast), settings.ollamaModel, promptVersion, String(settings.qualityFirst)].joined(separator: "|")
    }
}

struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self.value = value }
        else if let value = try? container.decode(Bool.self) { self.value = value }
        else if let value = try? container.decode([String].self) { self.value = value }
        else if let value = try? container.decode([String: String].self) { self.value = value }
        else { self.value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let value as String: try container.encode(value)
        case let value as Bool: try container.encode(value)
        case let value as [String]: try container.encode(value)
        case let value as [String: String]: try container.encode(value)
        case let value as [String: Any]: try container.encode(value.mapValues(AnyCodable.init))
        default: try container.encodeNil()
        }
    }
}

struct OllamaRequest: Encodable {
    let model: String
    let prompt: String
    let images: [String]
    let stream: Bool
    let format: [String: AnyCodable]
    let options: [String: Double]
    let keepAlive: String

    enum CodingKeys: String, CodingKey { case model, prompt, images, stream, format, options, keepAlive = "keep_alive" }
}

struct OllamaResponse: Decodable {
    let response: String
}

struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }
    let models: [Model]
}

enum LocalAIError: LocalizedError {
    case runtimeMissing
    case bundledModelMissing
    case runtimeStartFailed(String)
    case runtimeExited
    case runtimeTimedOut

    var errorDescription: String? {
        switch self {
        case .runtimeMissing:
            "The embedded Ollama executable is missing from this app."
        case .bundledModelMissing:
            "No bundled instruct VL model found (expected qwen3-vl:8b-instruct or qwen3-vl:4b-instruct)."
        case .runtimeStartFailed(let detail):
            "The bundled AI runtime could not start: \(detail)"
        case .runtimeExited:
            "The bundled AI runtime exited during startup."
        case .runtimeTimedOut:
            "The bundled AI runtime did not become ready in time (large models need longer on first start)."
        }
    }
}

final class SynchronousDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedData: Data?
    private var storedStatusCode: Int?
    private var storedError: Error?

    var data: Data? {
        lock.lock()
        defer { lock.unlock() }
        return storedData
    }

    var statusCode: Int? {
        lock.lock()
        defer { lock.unlock() }
        return storedStatusCode
    }

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return storedError
    }

    func store(data: Data?, statusCode: Int?, error: Error?) {
        lock.lock()
        storedData = data
        storedStatusCode = statusCode
        storedError = error
        lock.unlock()
    }
}

struct AnalysisCacheFile: Codable {
    var values: [String: SceneAnalysis] = [:]
}

struct RenderStatusEntry: Codable {
    let fingerprint: String
    let outputName: String
}

final class RenderStatusStore: @unchecked Sendable {
    private let url: URL
    private var entries: [String: RenderStatusEntry]

    init(folder: URL) {
        url = folder.appendingPathComponent(".watermark-status.json")
        entries = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: RenderStatusEntry].self, from: $0) } ?? [:]
    }

    func isComplete(file: URL, settings: RenderSettings) -> Bool {
        guard let entry = entries[file.path], entry.fingerprint == fingerprint(file: file, settings: settings) else { return false }
        return FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent(entry.outputName).path)
    }

    func markComplete(file: URL, settings: RenderSettings, output: URL) {
        entries[file.path] = RenderStatusEntry(fingerprint: fingerprint(file: file, settings: settings), outputName: output.lastPathComponent)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func fingerprint(file: URL, settings: RenderSettings) -> String {
        let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return [String(values?.fileSize ?? 0), String(describing: values?.contentModificationDate ?? .distantPast), settings.text, settings.fontName, settings.corner.rawValue, settings.direction.rawValue, String(settings.opacity), String(settings.heightPercent), String(settings.bottomOffsetPercent), String(settings.jpegQuality), settings.outputFormat.rawValue, String(settings.autoEnhance), String(settings.aiSubjectEnhance), String(settings.qualityFirst), settings.analysisMode.rawValue, settings.ollamaModel, "enhancer-v3-skin-safe"].joined(separator: "|")
    }
}

final class AnalysisCache {
    private let url: URL
    private var file: AnalysisCacheFile

    init(folder: URL) {
        url = folder.appendingPathComponent(".watermark-ai-cache.json")
        file = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(AnalysisCacheFile.self, from: $0) } ?? AnalysisCacheFile()
    }

    func value(for key: String) -> SceneAnalysis? { file.values[key] }

    func store(_ value: SceneAnalysis, for key: String) {
        file.values[key] = value
        guard let data = try? JSONEncoder().encode(file) else { return }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".watermark-ai-cache-\(UUID().uuidString).tmp")
        try? data.write(to: temporary, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } else {
            try? FileManager.default.moveItem(at: temporary, to: url)
        }
    }
}

enum MeasurementEnhancer {
    /// Stronger but still bounded caps for batch auto-enhance on Mac (local only).
    private static let maxExposureStops = 0.72
    private static let maxShadowLift = 0.48
    private static let maxContrast = 0.14
    private static let maxVibrance = 0.22
    private static let maxSharpen = 0.45

    static func measure(_ image: CGImage) -> ImageMetrics {
        guard let providerData = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(providerData) else {
            return ImageMetrics(luminanceP20: 0.5, luminanceP50: 0.5, luminanceP99: 0.9, shadowFraction: 0, highlightHeadroom: 0.1, clippedChannelFraction: 0)
        }
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let samplesPerRow = max(1, image.width / 512)
        let samplesPerColumn = max(1, image.height / 512)
        var luminances: [Double] = []
        var clippedChannels = 0
        var channelCount = 0
        for y in stride(from: 0, to: image.height, by: samplesPerColumn) {
            for x in stride(from: 0, to: image.width, by: samplesPerRow) {
                let offset = y * image.bytesPerRow + x * bytesPerPixel
                let red = Double(bytes[offset]) / 255
                let green = Double(bytes[offset + min(1, bytesPerPixel - 1)]) / 255
                let blue = Double(bytes[offset + min(2, bytesPerPixel - 1)]) / 255
                luminances.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
                for channel in 0..<min(3, bytesPerPixel) {
                    channelCount += 1
                    if bytes[offset + channel] >= 254 { clippedChannels += 1 }
                }
            }
        }
        guard !luminances.isEmpty else {
            return ImageMetrics(luminanceP20: 0.5, luminanceP50: 0.5, luminanceP99: 0.9, shadowFraction: 0, highlightHeadroom: 0.1, clippedChannelFraction: 0)
        }
        luminances.sort()
        func percentile(_ percentile: Double) -> Double {
            luminances[min(luminances.count - 1, Int(Double(luminances.count - 1) * percentile))]
        }
        return ImageMetrics(
            luminanceP20: percentile(0.20),
            luminanceP50: percentile(0.50),
            luminanceP99: percentile(0.99),
            shadowFraction: Double(luminances.filter { $0 < 0.12 }.count) / Double(luminances.count),
            highlightHeadroom: max(0, 1 - percentile(0.99)),
            clippedChannelFraction: channelCount == 0 ? 0 : Double(clippedChannels) / Double(channelCount)
        )
    }

    /// Measurement-first plan. AI treatments *bias* strength instead of hard-gating to zero.
    static func plan(metrics: ImageMetrics, analysis: SceneAnalysis?, iso: Double? = nil, qualityFirst: Bool = false, protectSkin: Bool = false) -> EnhancementPlan {
        let treatment = analysis?.recommendedTreatment
        let peopleScene = analysis?.sceneCategory == .portrait || analysis?.sceneCategory == .event
        let skinSafe = protectSkin || peopleScene
        let preserveColor = analysis?.preserveColoredLighting == true || treatment == .preserveStageLighting
        let protectHighlights = metrics.highlightHeadroom < 0.04 || analysis?.highlightsNeedProtection == true
        let noisyShadows = metrics.shadowFraction > 0.65 && metrics.luminanceP20 < 0.04
        let isoValue = iso ?? 400
        let highISO = isoValue >= 3200
        // Keep quality-first modest; prior 1.12 boost + vibrance/sharpen stacked plastic skin.
        let qualityBoost = qualityFirst ? (skinSafe ? 1.04 : 1.08) : 1.0

        var exposure = protectHighlights ? 0 : max(0, (0.36 - metrics.luminanceP50) * 1.55 * qualityBoost)
        var shadowLift = noisyShadows ? 0 : max(0, (0.20 - metrics.luminanceP20) * 1.75 * qualityBoost)
        var contrast = max(0, (0.42 - metrics.luminanceP50) * 0.35 + (metrics.luminanceP99 - metrics.luminanceP20 < 0.55 ? 0.06 : 0))
        var vibrance = preserveColor ? 0 : max(0, 0.08 + (0.30 - metrics.luminanceP50) * 0.25)
        var sharpen = 0.18 + min(0.2, metrics.shadowFraction * 0.15)

        if highISO {
            // Avoid crunchy grain when lifting Z6 high-ISO shadows.
            shadowLift *= 0.82
            sharpen *= 0.55
            contrast *= 0.90
        }
        if qualityFirst && !highISO && !skinSafe {
            sharpen *= 1.08
            vibrance *= preserveColor ? 0 : 1.05
        }

        if skinSafe {
            // People: prefer gentle tone; avoid orange/crunchy skin from vibrance + luminance sharpen.
            exposure *= 0.90
            shadowLift *= 0.92
            contrast *= 0.55
            vibrance = min(vibrance * 0.20, 0.04)
            sharpen *= 0.40
        }

        if analysis?.subjectsUnderexposed == true {
            shadowLift *= skinSafe ? 1.12 : 1.25
            exposure *= skinSafe ? 1.04 : 1.08
        }

        // Soft AI bias (never zero the whole plan on minimal / stage / review).
        switch treatment {
        case .minimal:
            exposure *= 0.40
            shadowLift *= 0.40
            contrast *= 0.45
            vibrance *= 0.35
            sharpen *= 0.55
        case .preserveStageLighting:
            exposure *= 0.50
            shadowLift *= 0.55
            contrast *= 0.40
            vibrance = 0
            sharpen *= 0.70
        case .review:
            exposure *= 0.60
            shadowLift *= 0.60
            contrast *= 0.55
            vibrance *= 0.50
            sharpen *= 0.70
        case .globalExposure:
            exposure *= skinSafe ? 1.08 : 1.20
            shadowLift *= 0.90
            contrast *= skinSafe ? 0.95 : 1.10
        case .shadowLift:
            exposure *= 0.85
            shadowLift *= skinSafe ? 1.15 : 1.30
            contrast *= 0.95
        case .subjectLift:
            exposure *= 0.90
            shadowLift *= skinSafe ? 1.12 : 1.20
            contrast *= skinSafe ? 0.95 : 1.05
            sharpen *= skinSafe ? 0.85 : 1.10
        case .none:
            break
        }

        if protectHighlights {
            exposure = min(exposure, 0.18)
            contrast *= 0.75
        }

        let vibranceCap = skinSafe ? 0.06 : maxVibrance
        let sharpenCap = skinSafe ? 0.18 : maxSharpen
        exposure = min(skinSafe ? 0.48 : maxExposureStops, exposure)
        shadowLift = min(skinSafe ? 0.36 : maxShadowLift, shadowLift)
        contrast = min(skinSafe ? 0.08 : maxContrast, contrast)
        vibrance = preserveColor ? 0 : min(vibranceCap, vibrance)
        sharpen = min(sharpenCap, sharpen)

        let highlightAmount: Double
        if protectHighlights {
            highlightAmount = 0.32
        } else if shadowLift > 0.02 {
            highlightAmount = skinSafe ? 0.05 : 0.08
        } else {
            highlightAmount = 0
        }

        return EnhancementPlan(
            exposureStops: exposure,
            shadowLift: shadowLift,
            highlightAmount: highlightAmount,
            contrastAmount: contrast,
            vibranceAmount: vibrance,
            sharpenAmount: sharpen,
            protectHighlights: protectHighlights,
            preserveColor: preserveColor,
            review: treatment == .review || metrics.clippedChannelFraction > 0.18
        )
    }

    static func noiseLevel(forISO iso: Double?, qualityFirst: Bool, protectSkin: Bool = false) -> Double {
        let value = iso ?? 400
        let base: Double
        switch value {
        case 6400...: base = 0.055
        case 3200..<6400: base = 0.042
        case 1600..<3200: base = 0.028
        case 800..<1600: base = 0.018
        // Do not denoise clean low-ISO frames — it waxes skin texture.
        default: base = 0
        }
        var level = qualityFirst ? min(0.08, base * 1.10) : base
        if protectSkin {
            level *= 0.30
        }
        return level
    }
}

enum ImageRenderer {
    static func render(file: URL, to folder: URL, settings: RenderSettings, log: WorkLog) throws -> URL {
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
                let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let iso = readISO(from: sourceProperties)
        var developedImage = try preparedImage(file: file, sourceImage: sourceImage, settings: settings)
        let hasFaces = imageContainsFaces(developedImage)
        let noise = MeasurementEnhancer.noiseLevel(forISO: iso, qualityFirst: settings.qualityFirst, protectSkin: hasFaces)
        if noise > 0.001 {
            developedImage = try denoisedImage(developedImage, noiseLevel: noise)
            log.add("\(file.lastPathComponent): denoise \(String(format: "%.3f", noise)) (ISO \(iso.map { String(Int($0)) } ?? "unknown")\(hasFaces ? ", skin-safe" : ""))")
        }
        let metrics = MeasurementEnhancer.measure(developedImage)
        let analysis = LocalAIAnalyzer.analyze(image: developedImage, file: file, settings: settings, outputFolder: folder, metrics: metrics, log: log)
        let peopleScene = analysis?.sceneCategory == .portrait || analysis?.sceneCategory == .event
        let protectSkin = hasFaces || peopleScene
        var plan = MeasurementEnhancer.plan(metrics: metrics, analysis: analysis, iso: iso, qualityFirst: settings.qualityFirst, protectSkin: protectSkin)
        let usedRawTherapee = settings.autoEnhance && isRaw(file) && rawTherapeeURL() != nil
        if usedRawTherapee && settings.qualityFirst {
            // RawTherapee already developed; keep a gentler measured polish instead of skipping CI entirely.
            plan = plan.scaled(by: protectSkin ? 0.45 : 0.62)
        }
        log.add("\(file.lastPathComponent): plan EV \(String(format: "%.2f", plan.exposureStops)), shadows \(String(format: "%.2f", plan.shadowLift)), contrast \(String(format: "%.2f", plan.contrastAmount)), vibrance \(String(format: "%.2f", plan.vibranceAmount))\(protectSkin ? ", skin-safe" : "")\(plan.preserveColor ? ", preserveColor" : "")\(plan.review ? ", review" : "")")

        let wantsGlobal = settings.autoEnhance && (!usedRawTherapee || settings.qualityFirst)
        let wantsSubject = settings.aiSubjectEnhance

        let image: CGImage
        if wantsGlobal && wantsSubject {
            let globallyEnhanced = try measuredEnhancedImage(developedImage, plan: plan, enabled: true)
            let boostFactor = analysis?.subjectsUnderexposed == true || analysis?.recommendedTreatment == .subjectLift ? 0.45 : 0.28
            let subjectBoost = protectSkin ? plan.skinSafeSubjectBoost(factor: boostFactor) : plan.scaled(by: boostFactor)
            image = try subjectEnhancedImage(globallyEnhanced, plan: subjectBoost)
            log.add("\(file.lastPathComponent): enhance path global+subject (qualityFirst=\(settings.qualityFirst)\(protectSkin ? ", skin-safe subject" : ""))")
        } else if wantsSubject {
            let subjectPlan = protectSkin ? plan.skinSafeSubjectBoost(factor: 1.0) : plan
            image = try subjectEnhancedImage(developedImage, plan: subjectPlan)
            log.add("\(file.lastPathComponent): enhance path subject-only measured\(protectSkin ? " (skin-safe)" : "")")
        } else if wantsGlobal {
            image = try measuredEnhancedImage(developedImage, plan: plan, enabled: true)
            log.add("\(file.lastPathComponent): enhance path global measured")
        } else {
            image = developedImage
            if usedRawTherapee {
                log.add("\(file.lastPathComponent): enhance path RawTherapee develop only")
            }
        }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let fontSize = max(8, height * settings.heightPercent / 100)
        let font = NSFont(name: settings.fontName, size: fontSize) ?? .systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(settings.opacity),
            .strokeColor: NSColor.black.withAlphaComponent(settings.opacity * 0.65),
            .strokeWidth: -2.5
        ]
        let string = NSAttributedString(string: settings.text, attributes: attributes)
        let textSize = string.size()
        let margin = max(12, height * 0.025)
        let bottomOffset = height * settings.bottomOffsetPercent / 100
        let origin: CGPoint
        switch settings.corner {
        case .topLeft: origin = CGPoint(x: margin, y: height - margin - textSize.height)
        case .topRight: origin = CGPoint(x: width - margin - textSize.width, y: height - margin - textSize.height)
        case .bottomLeft: origin = CGPoint(x: margin, y: margin + bottomOffset)
        case .bottomRight: origin = CGPoint(x: width - margin - textSize.width, y: margin + bottomOffset)
        }
        let center = CGPoint(x: origin.x + textSize.width / 2, y: origin.y + textSize.height / 2)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: settings.direction.angle)
        string.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
        context.restoreGState()
        NSGraphicsContext.restoreGraphicsState()

        guard let result = context.makeImage(), let type = outputType(for: file, format: settings.outputFormat) else { throw CocoaError(.coderInvalidValue) }
        let outputURL = uniqueOutputURL(for: file, in: folder, type: type)
        let temporaryURL = folder.appendingPathComponent(".watermark-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard let destination = CGImageDestinationCreateWithURL(temporaryURL as CFURL, type.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        var properties = sourceProperties
        if type == .jpeg { properties[kCGImageDestinationLossyCompressionQuality] = settings.jpegQuality }
        CGImageDestinationAddImage(destination, result, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try FileManager.default.moveItem(at: temporaryURL, to: outputURL)
        return outputURL
    }

    private static func outputType(for file: URL, format: OutputFormat) -> UTType? {
        if format == .jpeg { return UTType.jpeg }
        return switch file.pathExtension.lowercased() {
        case "jpg", "jpeg": UTType.jpeg
        case "png": UTType.png
        case "tif", "tiff": UTType.tiff
        case "heic", "heif": UTType.heic
        default: nil
        }
    }

    private static func ciContext() -> CIContext {
        let working = CGColorSpace(name: CGColorSpace.extendedSRGB) ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let output = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: working,
            .outputColorSpace: output
        ])
    }

    private static func measuredEnhancedImage(_ image: CGImage, plan: EnhancementPlan, enabled: Bool) throws -> CGImage {
        guard enabled, plan.hasAdjustments else { return image }
        let input = CIImage(cgImage: image)
        let context = ciContext()
        let output = applyMeasuredPlan(to: input, plan: plan)
        guard let enhanced = context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()) else {
            throw CocoaError(.coderInvalidValue)
        }
        return enhanced
    }

    private static func applyMeasuredPlan(to input: CIImage, plan: EnhancementPlan) -> CIImage {
        var output = input
        if plan.exposureStops > 0.001, let exposure = CIFilter(name: "CIExposureAdjust") {
            exposure.setValue(output, forKey: kCIInputImageKey)
            exposure.setValue(plan.exposureStops, forKey: kCIInputEVKey)
            output = exposure.outputImage ?? output
        }
        if plan.shadowLift > 0.001 || plan.highlightAmount > 0.001, let shadows = CIFilter(name: "CIHighlightShadowAdjust") {
            shadows.setValue(output, forKey: kCIInputImageKey)
            shadows.setValue(plan.shadowLift, forKey: "inputShadowAmount")
            shadows.setValue(plan.highlightAmount, forKey: "inputHighlightAmount")
            output = shadows.outputImage ?? output
        }
        if plan.contrastAmount > 0.001 || (!plan.preserveColor && plan.vibranceAmount > 0.001), let color = CIFilter(name: "CIColorControls") {
            color.setValue(output, forKey: kCIInputImageKey)
            color.setValue(1.0 + plan.contrastAmount, forKey: kCIInputContrastKey)
            color.setValue(1.0, forKey: kCIInputSaturationKey)
            color.setValue(0.0, forKey: kCIInputBrightnessKey)
            output = color.outputImage ?? output
        }
        if !plan.preserveColor, plan.vibranceAmount > 0.001, let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(output, forKey: kCIInputImageKey)
            vibrance.setValue(plan.vibranceAmount, forKey: "inputAmount")
            output = vibrance.outputImage ?? output
        }
        if plan.sharpenAmount > 0.001, let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(output, forKey: kCIInputImageKey)
            sharpen.setValue(plan.sharpenAmount, forKey: kCIInputSharpnessKey)
            output = sharpen.outputImage ?? output
        }
        return output
    }

    private static func denoisedImage(_ image: CGImage, noiseLevel: Double) throws -> CGImage {
        guard noiseLevel > 0.001, let filter = CIFilter(name: "CINoiseReduction") else { return image }
        let input = CIImage(cgImage: image)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(noiseLevel, forKey: "inputNoiseLevel")
        filter.setValue(max(0.2, 0.55 - noiseLevel * 3), forKey: "inputSharpness")
        let context = ciContext()
        guard let output = filter.outputImage,
              let result = context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()) else {
            return image
        }
        return result
    }

    private static func readISO(from properties: [CFString: Any]) -> Double? {
        guard let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return nil }
        if let ratings = exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber], let first = ratings.first {
            return first.doubleValue
        }
        if let ratings = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let first = ratings.first {
            return Double(first)
        }
        return nil
    }

    private static func preparedImage(file: URL, sourceImage: CGImage, settings: RenderSettings) throws -> CGImage {
        // Develop RAW only here. Measured / subject enhance runs after metrics + AI analysis.
        if settings.autoEnhance && isRaw(file), let rawTherapee = rawTherapeeURL() {
            return try rawTherapeeImage(file: file, sourceImage: sourceImage, executable: rawTherapee)
        }
        return sourceImage
    }

    private static func rawTherapeeImage(file: URL, sourceImage: CGImage, executable: URL) throws -> CGImage {

        let temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatermarkTool-RAW-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryFolder) }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["-q", "-d", "-j100", "-o", temporaryFolder.path, "-Y", "-c", file.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let renderedURL = try? FileManager.default.contentsOfDirectory(at: temporaryFolder, includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased() == "jpg" }),
              let renderedSource = CGImageSourceCreateWithURL(renderedURL as CFURL, nil),
              let renderedImage = CGImageSourceCreateImageAtIndex(renderedSource, 0, nil) else {
            return sourceImage
        }
        return renderedImage
    }

    private static func imageContainsFaces(_ image: CGImage) -> Bool {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNDetectFaceRectanglesRequest()
        do {
            try handler.perform([request])
            return !(request.results ?? []).isEmpty
        } catch {
            return false
        }
    }

    private static func subjectEnhancedImage(_ image: CGImage, plan: EnhancementPlan) throws -> CGImage {
        guard plan.hasAdjustments else { return image }
        let handler = VNImageRequestHandler(cgImage: image)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first else { return image }
        let maskBuffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        let original = CIImage(cgImage: image)
        let adjusted = applyMeasuredPlan(to: original, plan: plan)
        let rawMask = CIImage(cvPixelBuffer: maskBuffer)
        let featherRadius = max(2.5, min(18.0, Double(max(image.width, image.height)) * 0.004))
        let featheredMask: CIImage
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(rawMask, forKey: kCIInputImageKey)
            blur.setValue(featherRadius, forKey: kCIInputRadiusKey)
            let blurred = blur.outputImage ?? rawMask
            featheredMask = blurred.cropped(to: original.extent)
        } else {
            featheredMask = rawMask
        }
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return image }
        blend.setValue(adjusted, forKey: kCIInputImageKey)
        blend.setValue(original, forKey: kCIInputBackgroundImageKey)
        blend.setValue(featheredMask, forKey: kCIInputMaskImageKey)
        let context = ciContext()
        guard let output = blend.outputImage,
              let result = context.createCGImage(output, from: original.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()) else {
            return image
        }
        return result
    }

    private static func rawTherapeeURL() -> URL? {
        [
            "/opt/homebrew/bin/rawtherapee-cli",
            "/usr/local/bin/rawtherapee-cli",
            "/Applications/RawTherapee.app/Contents/MacOS/rawtherapee-cli"
        ].lazy.map(URL.init(fileURLWithPath:)).first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private static func uniqueOutputURL(for file: URL, in folder: URL, type: UTType) -> URL {
        let stem = file.deletingPathExtension().lastPathComponent + "-watermarked"
        let extensionName = type.preferredFilenameExtension ?? "jpg"
        var candidate = folder.appendingPathComponent("\(stem).\(extensionName)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem)-\(suffix).\(extensionName)")
            suffix += 1
        }
        return candidate
    }

    private static func isRaw(_ file: URL) -> Bool {
        ["dng", "raw", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2"].contains(file.pathExtension.lowercased())
    }
}