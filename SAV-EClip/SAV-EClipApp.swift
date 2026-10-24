import SwiftUI
import UIKit

#if DEBUG
/// UI-test appearance must be applied before first paint. `XCUIDevice.appearance`
/// is ignored on some CI simulators; `-AppleInterfaceStyle` plus this hook
/// force `overrideUserInterfaceStyle` and SwiftUI `preferredColorScheme`.
private struct UITestAppearanceOverride: ViewModifier {
    private let scheme: ColorScheme?
    private let style: UIUserInterfaceStyle

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitest-force-dark") {
            scheme = .dark
            style = .dark
        } else if arguments.contains("--uitest-force-light") {
            scheme = .light
            style = .light
        } else {
            scheme = nil
            style = .unspecified
        }
    }

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(scheme)
            .background(UITestWindowAppearanceSetter(style: style))
    }
}

private struct UITestWindowAppearanceSetter: UIViewRepresentable {
    let style: UIUserInterfaceStyle

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        apply(from: uiView)
        DispatchQueue.main.async { apply(from: uiView) }
    }

    private func apply(from view: UIView) {
        guard style != .unspecified else { return }
        view.window?.overrideUserInterfaceStyle = style
        view.window?.rootViewController?.overrideUserInterfaceStyle = style
    }
}
#endif

@main
struct SAV_EClipApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            ClipContentView()
                .modifier(UITestAppearanceOverride())
            #else
            ClipContentView()
            #endif
        }
    }
}
