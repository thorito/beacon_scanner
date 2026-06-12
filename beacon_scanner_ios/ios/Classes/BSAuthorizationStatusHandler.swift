import Foundation
import Flutter
import CoreBluetooth

public class BSAuthorizationStatusHandler: NSObject, FlutterStreamHandler {
    
    public var instance: BeaconScannerPlugin?
    
    public init(beaconScannerPlugin: BeaconScannerPlugin) {
        super.init()
        self.instance = beaconScannerPlugin
    }
    
    // MARK: - Flutter Stream Handler
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        instance?.flutterEventSinkAuthorization = nil
        return nil
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        instance?.initializeLocationManager()
        instance?.flutterEventSinkAuthorization = events
        return nil
    }
}