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

        // super sets up window + rootViewController. Must run BEFORE we
        // can grab the binaryMessenger.
        let result = super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )

        if let controller = window?.rootViewController as? FlutterViewController {
            print("[AppDelegate] FlutterViewController obtained; registering MLPipelineCoordinator")
            MLPipelineCoordinator.register(with: controller.binaryMessenger)
        } else {
            print("[AppDelegate] ERROR: rootViewController is not a FlutterViewController (type=\(String(describing: type(of: window?.rootViewController)))). MLPipeline not registered.")
        }

        print("[AppDelegate] didFinishLaunchingWithOptions done (result=\(result))")
        return result
    }
}
