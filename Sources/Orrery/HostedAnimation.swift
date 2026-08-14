import SwiftUI

/// 毎フレーム更新される絵を、独立したSwiftUIの階層に隔離して載せる。
/// そのまま置くと更新のたびに画面全体のレイアウトが走ってしまうため。
struct HostedAnimation<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content)
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ view: NSHostingView<Content>, context: Context) {
        view.rootView = content
    }
}
