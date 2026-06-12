import Flutter
import UIKit
import CoreBluetooth
import CoreLocation

public class BeaconScannerPlugin: NSObject, FlutterPlugin, CLLocationManagerDelegate, CBCentralManagerDelegate, CBPeripheralManagerDelegate {
    
    public var flutterEventSinkRanging: FlutterEventSink?
    public var flutterEventSinkMonitoring: FlutterEventSink?
    public var flutterEventSinkBluetooth: FlutterEventSink?
    public var flutterEventSinkAuthorization: FlutterEventSink?
    
    private var defaultLocationAuthorizationType: CLAuthorizationStatus = .authorizedAlways
    private var shouldStartAdvertise: Bool = false
    
    private var locationManager: CLLocationManager?
    private var bluetoothManager: CBCentralManager?
    private var peripheralManager: CBPeripheralManager?
    private var regionRanging: NSMutableArray?
    private var regionMonitoring: NSMutableArray?
    private var beaconPeripheralData: [String: Any]?
    
    private var rangingHandler: BSRangingStreamHandler?
    private var monitoringHandler: BSMonitoringStreamHandler?
    private var bluetoothHandler: BSBluetoothStateHandler?
    private var authorizationHandler: BSAuthorizationStatusHandler?
    
    private var flutterResult: FlutterResult?
    private var flutterBluetoothResult: FlutterResult?
    private var flutterBroadcastResult: FlutterResult?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "plugins.lukangagames.com/beacon_scanner_android",
                                         binaryMessenger: registrar.messenger())
        let instance = BeaconScannerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        instance.rangingHandler = BSRangingStreamHandler(beaconScannerPlugin: instance)
        let streamChannelRanging = FlutterEventChannel(name: "beacon_scanner_event_ranging",
                                                     binaryMessenger: registrar.messenger())
        streamChannelRanging.setStreamHandler(instance.rangingHandler)
        
        instance.monitoringHandler = BSMonitoringStreamHandler(beaconScannerPlugin: instance)
        let streamChannelMonitoring = FlutterEventChannel(name: "beacon_scanner_event_monitoring",
                                                        binaryMessenger: registrar.messenger())
        streamChannelMonitoring.setStreamHandler(instance.monitoringHandler)
        
        instance.bluetoothHandler = BSBluetoothStateHandler(beaconScannerPlugin: instance)
        let streamChannelBluetooth = FlutterEventChannel(name: "beacon_scanner_bluetooth_state_changed",
                                                       binaryMessenger: registrar.messenger())
        streamChannelBluetooth.setStreamHandler(instance.bluetoothHandler)
        
        instance.authorizationHandler = BSAuthorizationStatusHandler(beaconScannerPlugin: instance)
        let streamChannelAuthorization = FlutterEventChannel(name: "beacon_scanner_authorization_status_changed",
                                                           binaryMessenger: registrar.messenger())
        streamChannelAuthorization.setStreamHandler(instance.authorizationHandler)
    }
    
    public override init() {
        super.init()
        defaultLocationAuthorizationType = .authorizedAlways
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            initializeLocationManager()
            initializeCentralManager()
            result(true)
            
        case "initializeAndCheckScanning":
            initialize(with: result)
            
        case "setLocationAuthorizationTypeDefault":
            if let argumentString = call.arguments as? String {
                switch argumentString {
                case "ALWAYS":
                    defaultLocationAuthorizationType = .authorizedAlways
                    result(true)
                case "WHEN_IN_USE":
                    defaultLocationAuthorizationType = .authorizedWhenInUse
                    result(true)
                default:
                    result(false)
                }
            } else {
                result(false)
            }
            
        case "authorizationStatus":
            initializeLocationManager()
            let status: String
            switch CLLocationManager.authorizationStatus() {
            case .notDetermined:
                status = "NOT_DETERMINED"
            case .restricted:
                status = "RESTRICTED"
            case .denied:
                status = "DENIED"
            case .authorizedAlways:
                status = "ALWAYS"
            case .authorizedWhenInUse:
                status = "WHEN_IN_USE"
            @unknown default:
                status = "NOT_DETERMINED"
            }
            result(status)
            
        case "checkLocationServicesIfEnabled":
            result(CLLocationManager.locationServicesEnabled())
            
        case "bluetoothState":
            flutterBluetoothResult = result
            initializeCentralManager()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard let bluetoothResult = self.flutterBluetoothResult else { return }
                
                let state: String
                switch self.bluetoothManager?.state {
                case .unknown:
                    state = "STATE_UNKNOWN"
                case .resetting:
                    state = "STATE_RESETTING"
                case .unsupported:
                    state = "STATE_UNSUPPORTED"
                case .unauthorized:
                    state = "STATE_UNAUTHORIZED"
                case .poweredOff:
                    state = "STATE_OFF"
                case .poweredOn:
                    state = "STATE_ON"
                case .none:
                    state = "STATE_UNKNOWN"
                @unknown default:
                    state = "STATE_UNKNOWN"
                }
                
                bluetoothResult(state)
                self.flutterBluetoothResult = nil
            }
            
        case "requestAuthorization":
            if locationManager != nil {
                flutterResult = result
                requestDefaultLocationManagerAuthorization()
            } else {
                result(true)
            }
            
        case "openBluetoothSettings":
            result(true)
            
        case "openLocationSettings":
            result(true)
            
        case "setScanPeriod":
            result(true)
            
        case "setBetweenScanPeriod":
            result(true)
            
        case "openApplicationSettings":
            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsUrl)
            }
            result(true)
            
        case "close":
            stopRangingBeacon()
            stopMonitoringBeacon()
            result(true)
            
        case "startBroadcast":
            flutterBroadcastResult = result
            startBroadcast(arguments: call.arguments)
            
        case "stopBroadcast":
            peripheralManager?.stopAdvertising()
            result(nil)
            
        case "isBroadcasting":
            result(peripheralManager?.isAdvertising ?? false)
            
        case "isBroadcastSupported":
            result(true)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    public func initializeCentralManager() {
        if bluetoothManager == nil {
            bluetoothManager = CBCentralManager(delegate: self, queue: .main)
        }
    }
    
    public func initializeLocationManager() {
        if locationManager == nil {
            locationManager = CLLocationManager()
            locationManager?.delegate = self
        }
    }
    
    private func startBroadcast(arguments: Any?) {
        guard let dict = arguments as? [String: Any] else { return }
        
        var measuredPower: NSNumber?
        if let txPower = dict["txPower"] as? NSNumber {
            measuredPower = txPower
        }
        
        guard let region = BSUtils.regionFromDictionary(dict) else { return }
        
        shouldStartAdvertise = true
        beaconPeripheralData = region.peripheralData(withMeasuredPower: measuredPower)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Flutter Beacon Ranging
    
    public func startRangingBeacon(withCall arguments: Any?) {
        if regionRanging != nil {
            regionRanging?.removeAllObjects()
        } else {
            regionRanging = NSMutableArray()
        }
        
        guard let array = arguments as? [[String: Any]] else { return }
        
        for dict in array {
            if let region = BSUtils.regionFromDictionary(dict) {
                regionRanging?.add(region)
            }
        }
        
        if let regions = regionRanging {
            for case let region as CLBeaconRegion in regions {
                print("START: \(region)")
                locationManager?.startRangingBeacons(in: region)
            }
        }
    }
    
    public func stopRangingBeacon() {
        if let regions = regionRanging {
            for case let region as CLBeaconRegion in regions {
                locationManager?.stopRangingBeacons(in: region)
            }
        }
        flutterEventSinkRanging = nil
    }
    
    // MARK: - Flutter Beacon Monitoring
    
    public func startMonitoringBeacon(withCall arguments: Any?) {
        if regionMonitoring != nil {
            regionMonitoring?.removeAllObjects()
        } else {
            regionMonitoring = NSMutableArray()
        }
        
        guard let array = arguments as? [[String: Any]] else { return }
        
        for dict in array {
            if let region = BSUtils.regionFromDictionary(dict) {
                regionMonitoring?.add(region)
            }
        }
        
        if let regions = regionMonitoring {
            for case let region as CLBeaconRegion in regions {
                print("START: \(region)")
                locationManager?.startMonitoring(for: region)
            }
        }
    }
    
    public func stopMonitoringBeacon() {
        if let regions = regionMonitoring {
            for case let region as CLBeaconRegion in regions {
                locationManager?.stopMonitoring(for: region)
            }
        }
        flutterEventSinkMonitoring = nil
    }
    
    // MARK: - Flutter Beacon Initialize
    
    private func initialize(with result: @escaping FlutterResult) {
        flutterResult = result
        initializeLocationManager()
        initializeCentralManager()
    }
    
    // MARK: - Bluetooth Manager Delegate
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        var message: String?
        let stateString: String
        
        switch central.state {
        case .unknown:
            stateString = "STATE_UNKNOWN"
            message = "CBManagerStateUnknown"
        case .resetting:
            stateString = "STATE_RESETTING"
            message = "CBManagerStateResetting"
        case .unsupported:
            stateString = "STATE_UNSUPPORTED"
            message = "CBManagerStateUnsupported"
        case .unauthorized:
            stateString = "STATE_UNAUTHORIZED"
            message = "CBManagerStateUnauthorized"
        case .poweredOff:
            stateString = "STATE_OFF"
            message = "CBManagerStatePoweredOff"
        case .poweredOn:
            stateString = "STATE_ON"
            message = nil
            
            if CLLocationManager.locationServicesEnabled() {
                switch CLLocationManager.authorizationStatus() {
                case .notDetermined:
                    requestDefaultLocationManagerAuthorization()
                    return
                case .denied:
                    message = "CLAuthorizationStatusDenied"
                case .restricted:
                    message = "CLAuthorizationStatusRestricted"
                default:
                    break
                }
            } else {
                message = "LocationServicesDisabled"
            }
        @unknown default:
            stateString = "STATE_UNKNOWN"
            message = "CBManagerStateUnknown"
        }
        
        if let bluetoothResult = flutterBluetoothResult {
            bluetoothResult(stateString)
            flutterBluetoothResult = nil
            return
        }
        
        flutterEventSinkBluetooth?(stateString)
        
        if let result = flutterResult {
            if let errorMessage = message {
                result(FlutterError(code: "Beacon", message: errorMessage, details: nil))
            } else {
                result(nil)
            }
        }
    }
    
    // MARK: - Location Manager Delegate
    
    private func requestDefaultLocationManagerAuthorization() {
        switch defaultLocationAuthorizationType {
        case .authorizedWhenInUse:
            locationManager?.requestWhenInUseAuthorization()
        case .authorizedAlways:
            fallthrough
        default:
            locationManager?.requestAlwaysAuthorization()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        var message: String?
        let statusString: String
        
        switch status {
        case .authorizedAlways:
            statusString = "ALWAYS"
        case .authorizedWhenInUse:
            statusString = "WHEN_IN_USE"
        case .denied:
            statusString = "DENIED"
            message = "CLAuthorizationStatusDenied"
        case .restricted:
            statusString = "RESTRICTED"
            message = "CLAuthorizationStatusRestricted"
        case .notDetermined:
            statusString = "NOT_DETERMINED"
            message = "CLAuthorizationStatusNotDetermined"
        @unknown default:
            statusString = "NOT_DETERMINED"
            message = "CLAuthorizationStatusNotDetermined"
        }
        
        flutterEventSinkAuthorization?(statusString)
        
        if let result = flutterResult {
            if let errorMessage = message {
                result(FlutterError(code: "Beacon", message: errorMessage, details: nil))
            } else {
                result(nil)
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didRangeBeacons beacons: [CLBeacon], in region: CLBeaconRegion) {
        guard let eventSink = flutterEventSinkRanging else { return }
        
        let dictRegion = BSUtils.dictionaryFromCLBeaconRegion(region)
        let beaconArray = beacons.map { BSUtils.dictionaryFromCLBeacon($0) }
        
        eventSink([
            "region": dictRegion,
            "beacons": beaconArray
        ])
    }
    
    public func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let eventSink = flutterEventSinkMonitoring,
              let regions = regionMonitoring else { return }
        
        var matchedRegion: CLBeaconRegion?
        for case let r as CLBeaconRegion in regions {
            if region.identifier == r.identifier {
                matchedRegion = r
                break
            }
        }
        
        if let reg = matchedRegion {
            let dictRegion = BSUtils.dictionaryFromCLBeaconRegion(reg)
            eventSink([
                "event": "didEnterRegion",
                "region": dictRegion
            ])
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let eventSink = flutterEventSinkMonitoring,
              let regions = regionMonitoring else { return }
        
        var matchedRegion: CLBeaconRegion?
        for case let r as CLBeaconRegion in regions {
            if region.identifier == r.identifier {
                matchedRegion = r
                break
            }
        }
        
        if let reg = matchedRegion {
            let dictRegion = BSUtils.dictionaryFromCLBeaconRegion(reg)
            eventSink([
                "event": "didExitRegion",
                "region": dictRegion
            ])
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard let eventSink = flutterEventSinkMonitoring,
              let regions = regionMonitoring else { return }
        
        var matchedRegion: CLBeaconRegion?
        for case let r as CLBeaconRegion in regions {
            if region.identifier == r.identifier {
                matchedRegion = r
                break
            }
        }
        
        if let reg = matchedRegion {
            let dictRegion = BSUtils.dictionaryFromCLBeaconRegion(reg)
            let stateString: String
            
            switch state {
            case .inside:
                stateString = "INSIDE"
            case .outside:
                stateString = "OUTSIDE"
            case .unknown:
                stateString = "UNKNOWN"
            }
            
            eventSink([
                "event": "didDetermineStateForRegion",
                "region": dictRegion,
                "state": stateString
            ])
        }
    }
    
    // MARK: - Peripheral Manager Delegate
    
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            if shouldStartAdvertise {
                if let data = beaconPeripheralData {
                    peripheral.startAdvertising(data)
                }
                shouldStartAdvertise = false
            }
        default:
            break
        }
    }
    
    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        guard let broadcastResult = flutterBroadcastResult else { return }
        
        if let error = error {
            broadcastResult(FlutterError(code: "Broadcast", message: error.localizedDescription, details: error))
        } else {
            broadcastResult(peripheral.isAdvertising)
        }
        flutterBroadcastResult = nil
    }
}