import Foundation
import Flutter

public class BSRangingStreamHandler: NSObject, FlutterStreamHandler {
    
    public var instance: BeaconScannerPlugin?
    
    public init(beaconScannerPlugin: BeaconScannerPlugin) {
        super.init()
        self.instance = beaconScannerPlugin
    }
    
    // MARK: - Flutter Stream Handler
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        instance?.stopRangingBeacon()
        return nil
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        if let plugin = instance {
            plugin.flutterEventSinkRanging = events
            plugin.startRangingBeacon(withCall: arguments)
        }
        return nil
    }
}