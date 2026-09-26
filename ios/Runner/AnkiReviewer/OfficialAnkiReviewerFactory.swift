import Foundation
import Flutter

final class OfficialAnkiReviewerFactory: NSObject, FlutterPlatformViewFactory {
    static let viewType = "official_anki_reviewer"

    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        OfficialAnkiReviewerView(
            frame: frame,
            messenger: messenger,
            viewId: viewId,
            params: args as? [String: Any],
            assetLoader: { Self.loadReviewerAsset($0) }
        )
    }

    func createArgsCodec() -> (any FlutterMessageCodec & NSObjectProtocol) {
        FlutterStandardMessageCodec.sharedInstance()
    }

    /// Reviewer assets live inside the Flutter bundle
    /// (App.framework/flutter_assets/assets/anki_reviewer/...).
    static func loadReviewerAsset(_ name: String) -> Data? {
        let key = FlutterDartProject.lookupKey(forAsset: "assets/anki_reviewer/\(name)")
        let candidates: [URL?] = [
            Bundle.main.url(forResource: key, withExtension: nil),
            Bundle.main.privateFrameworksURL?.appendingPathComponent("App.framework/\(key)"),
            Bundle.main.bundleURL.appendingPathComponent("Frameworks/App.framework/\(key)"),
        ]
        for candidate in candidates {
            if let url = candidate, let data = try? Data(contentsOf: url) {
                return data
            }
        }
        NSLog("[OfficialAnkiReviewer] missing reviewer asset %@", name)
        return nil
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        registrar.register(
            OfficialAnkiReviewerFactory(messenger: registrar.messenger()),
            withId: viewType
        )
    }
}
