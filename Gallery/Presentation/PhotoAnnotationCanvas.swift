import PencilKit
import SwiftUI

enum PhotoMarkupTool: String, CaseIterable, Identifiable {
    case pen
    case pencil
    case marker
    case eraser

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .pencil: "pencil"
        case .marker: "highlighter"
        case .eraser: "eraser"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .pen: "Caneta"
        case .pencil: "Lápis"
        case .marker: "Marca-texto"
        case .eraser: "Borracha"
        }
    }

    var pencilKitTool: PKTool {
        switch self {
        case .pen:
            PKInkingTool(.pen, color: .black, width: 4)
        case .pencil:
            PKInkingTool(.pencil, color: .black, width: 5)
        case .marker:
            PKInkingTool(.marker, color: .systemYellow, width: 12)
        case .eraser:
            PKEraserTool(.vector)
        }
    }
}

struct PhotoAnnotationCanvas: UIViewRepresentable {
    @Binding var drawingData: Data
    var selectedTool: PhotoMarkupTool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isRulerActive = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = selectedTool.pencilKitTool
        canvas.overrideUserInterfaceStyle = .light
        context.coordinator.selectedTool = selectedTool
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.selectedTool != selectedTool {
            canvas.tool = selectedTool.pencilKitTool
            context.coordinator.selectedTool = selectedTool
        }
        let current = canvas.drawing.dataRepresentation()
        guard current != drawingData else { return }
        if drawingData.isEmpty {
            canvas.drawing = PKDrawing()
        } else if let drawing = try? PKDrawing(data: drawingData) {
            canvas.drawing = drawing
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PhotoAnnotationCanvas
        var selectedTool: PhotoMarkupTool = .pen

        init(parent: PhotoAnnotationCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawingData = canvasView.drawing.strokes.isEmpty
                ? Data()
                : canvasView.drawing.dataRepresentation()
        }
    }
}
