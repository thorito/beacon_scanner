import Foundation
import CoreLocation

public class BSUtils: NSObject {
    
    public static func dictionaryFromCLBeacon(_ beacon: CLBeacon) -> [String: Any] {
        let proximity: String
        switch beacon.proximity {
        case .unknown:
            proximity = "unknown"
        case .immediate:
            proximity = "immediate"
        case .near:
            proximity = "near"
        case .far:
            proximity = "far"
        @unknown default:
            proximity = "unknown"
        }
        
        return [
            "proximityUUID": beacon.uuid.uuidString,
            "major": beacon.major,
            "minor": beacon.minor,
            "rssi": beacon.rssi,
            "accuracy": beacon.accuracy,
            "proximity": proximity
        ]
    }
    
    public static func dictionaryFromCLBeaconRegion(_ region: CLBeaconRegion) -> [String: Any] {
        let major: Any = region.major ?? NSNull()
        let minor: Any = region.minor ?? NSNull()
        
        return [
            "identifier": region.identifier,
            "proximityUUID": region.uuid.uuidString,
            "major": major,
            "minor": minor
        ]
    }
    
    public static func regionFromDictionary(_ dict: [String: Any]) -> CLBeaconRegion? {
        guard let identifier = dict["identifier"] as? String,
              let proximityUUID = dict["proximityUUID"] as? String,
              let uuid = UUID(uuidString: proximityUUID) else {
            return nil
        }
        
        let major = dict["major"] as? NSNumber
        let minor = dict["minor"] as? NSNumber
        
        if let major = major, let minor = minor {
            return CLBeaconRegion(uuid: uuid, major: major.uint16Value, minor: minor.uint16Value, identifier: identifier)
        } else if let major = major {
            return CLBeaconRegion(uuid: uuid, major: major.uint16Value, identifier: identifier)
        } else {
            return CLBeaconRegion(uuid: uuid, identifier: identifier)
        }
    }
}