import Foundation

/// Resolve the shipped SwiftPM resources before considering the development checkout.
/// The generated Bundle.module accessor searches an app-root path and can fatalError;
/// signed macOS apps instead embed resource bundles inside Contents/Resources.
enum AppResources {
    static let module: Bundle = {
        let main = Bundle.main
        let url = main.bundleURL.appendingPathComponent("Contents/Resources/PokeTokenBar_PokeTokenBar.bundle")
        if let bundled = Bundle(url: url) { return bundled }
        #if SWIFT_PACKAGE
        if main.bundleURL.pathExtension != "app" { return Bundle.module }
        #endif
        return main
    }()
}
