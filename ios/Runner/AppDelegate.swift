import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        print("[AppDelegate] didFinishLaunchingWithOptions start")
        GeneratedPluginRegistrant.register(with: self)

        let result = super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )

        // Use the FlutterAppDelegate's plugin registrar rather than reaching
        // through window?.rootViewController. In recent Flutter + iOS scene
        // lifecycles, the rootViewController is a plain UIViewController at
        // this point; the FlutterViewController is installed later. The
        // registrar bypasses that and goes via the FlutterEngine directly.
        if let registrar = self.registrar(forPlugin: "MLPipelineCoordinator") {
            print("[AppDelegate] Got plugin registrar; registering MLPipelineCoordinator")
            MLPipelineCoordinator.register(with: registrar.messenger())
        } else {
            print("[AppDelegate] ERROR: registrar(forPlugin:) returned nil — MLPipeline not registered")
        }

        print("[AppDelegate] didFinishLaunchingWithOptions done (result=\(result))")
        return result
    }
}
