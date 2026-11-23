import AppKit
import SwiftUI

struct ProcessPanelVisibility: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ProcessPanelVisibilityView {
        let view = ProcessPanelVisibilityView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: ProcessPanelVisibilityView, context: Context) {
        view.onChange = onChange
    }

    static func dismantleNSView(_ view: ProcessPanelVisibilityView, coordinator: ()) {
        view.stopObserving()
    }
}

final class ProcessPanelVisibilityView: NSView {
    var onChange: ((Bool) -> Void)?
    private var visibilityObservation: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else { return }
        // MenuBarExtra can retain its content after ordering the native window out.
        visibilityObservation = window.observe(\.isVisible, options: [.initial, .new]) { [weak self, weak window] _, _ in
            DispatchQueue.main.async {
                guard let self, let window, self.window === window,
                      self.visibilityObservation != nil else { return }
                self.onChange?(window.isVisible)
            }
        }
    }

    func stopObserving() {
        visibilityObservation = nil
        onChange?(false)
    }
}
