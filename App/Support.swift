import AppKit
import Observation
import SwiftUI

/// Runs `body` on the main actor after `seconds`, unless the returned task is cancelled first.
@MainActor @discardableResult
func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) -> Task<Void, Never> {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled else { return }
        body()
    }
}

/// Calls `onChange` with the current value of `read`, then again whenever the observed value changes.
/// Lives for the app's lifetime: each change re-arms the tracking. (The `Observations` sequence crashed at
/// runtime here, so this uses `withObservationTracking`.)
@MainActor
func observeChanges<T: Equatable>(_ read: @escaping @MainActor () -> T, onChange: @escaping @MainActor (T) -> Void) {
    ChangeObserver(read: read, onChange: onChange).arm()
}

@MainActor
private final class ChangeObserver<T: Equatable> {
    let read: @MainActor () -> T
    let onChange: @MainActor (T) -> Void
    var last: T?

    init(read: @escaping @MainActor () -> T, onChange: @escaping @MainActor (T) -> Void) {
        self.read = read
        self.onChange = onChange
    }

    func arm() {
        let value = withObservationTracking { read() } onChange: { Task { @MainActor in self.arm() } }
        guard value != last else { return }
        last = value
        onChange(value)
    }
}

extension NSScreen {
    /// Stable per-display identifier (survives reboots and reconnects), used to key saved positions.
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

/// Hosts `content` at its ideal size, pinned to `alignment`, with `margin` of transparent room for shadows.
/// Reports the content's size so the owning panel can fit itself around it.
struct MeasuredContent<Content: View>: View {
    var alignment: Alignment
    var margin: CGFloat
    var onSize: @MainActor (CGSize) -> Void
    @ViewBuilder var content: Content

    var body: some View {
        content
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
            .padding(margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// An `NSHostingView` that never pushes size constraints onto its window; the panel controllers size it.
@MainActor
func makeHostingView<V: View>(_ view: V) -> NSHostingView<V> {
    let hosting = NSHostingView(rootView: view)
    hosting.sizingOptions = []
    return hosting
}
