/// In-memory interaction state shared across scene reloads for this app run.
/// A new app process starts with all boxes sealed and their flaps closed.
@MainActor
final class BoxSessionState {
    struct State {
        var isTapeRemoved = false
        var leftOpenAmount: Float = 0
        var rightOpenAmount: Float = 0
    }

    private var boxes: [String: State] = [:]

    subscript(boxName: String) -> State {
        get { boxes[boxName] ?? State() }
        set { boxes[boxName] = newValue }
    }
}
