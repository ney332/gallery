import SwiftData
import SwiftUI

@main
struct GalleryApp: App {
    private let modelContainer: ModelContainer
    @State private var libraryModel: GalleryLibraryModel

    @MainActor
    init() {
        let schema = Schema([PhotoAnnotationRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            modelContainer = container
            _libraryModel = State(initialValue: GalleryLibraryModel(
                photoRepository: PhotoKitLibraryRepository(),
                annotationRepository: SwiftDataAnnotationRepository(container: container)
            ))
        } catch {
            fatalError("Could not create annotation store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(libraryModel: libraryModel)
                .modelContainer(modelContainer)
        }
    }
}
