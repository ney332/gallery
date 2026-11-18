import PencilKit
import SwiftUI

struct PhotoAnnotationCanvas: UIViewRepresentable {
    @Binding var drawingData: Data

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isRulerActive = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.overrideUserInterfaceStyle = .light
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
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

        init(parent: PhotoAnnotationCanvas) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawingData = canvasView.drawing.strokes.isEmpty
                ? Data()
                : canvasView.drawing.dataRepresentation()
        }
    }
}
