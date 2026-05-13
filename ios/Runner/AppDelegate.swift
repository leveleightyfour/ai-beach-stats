import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        NSLog("[AppDelegate] didFinishLaunchingWithOptions start")
        GeneratedPluginRegistrant.register(with: self)

        // super sets up window + rootViewController. Must run BEFORE we
        // can grab the binaryMessenger.
        let result = super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions
        )

        if let controller = window?.rootViewController as? FlutterViewController {
            NSLog("[AppDelegate] FlutterViewController obtained; registering MLPipelineCoordinator")
            MLPipelineCoordinator.register(with: controller.binaryMessenger)
        } else {
            NSLog(
                "[AppDelegate] ERROR: rootViewController is not a FlutterViewController (type=%@). MLPipeline not registered.",
                String(describing: type(of: window?.rootViewController))
            )
        }

        NSLog("[AppDelegate] didFinishLaunchingWithOptions done (result=%@)", result ? "true" : "false")
        return result
    }
}
