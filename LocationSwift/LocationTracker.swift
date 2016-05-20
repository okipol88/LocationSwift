//
//  LocationTracker.swift
//  LocationSwift
//
//  Created by Emerson Carvalho on 5/21/15.
//  Copyright (c) 2015 Emerson Carvalho. All rights reserved.
//

import UIKit
import CoreLocation
import SLF4Swift

let LATITUDE = "latitude"
let LONGITUDE = "longitude"
let ACCURACY = "theAccuracy"

public class LocationTracker : NSObject, CLLocationManagerDelegate, UIAlertViewDelegate {

    private var logger: LoggerType {
        return SLF4Swift.defaultLogger
    }
    
    private var locations = [CLLocation]()
    public var myLastLocation: CLLocation?
    
    public var onLocationUpdate: ((CLLocation) -> ())?
    
    public var distanceFilter: CLLocationDistance {
        get {
            return LocationTracker.sharedLocationManager().distanceFilter
        }
        set {
            LocationTracker.sharedLocationManager().distanceFilter = newValue
        }
    }
    
   public var accuracy: CLLocationAccuracy {
        get {
            return LocationTracker.sharedLocationManager().desiredAccuracy
        }
        set {
            LocationTracker.sharedLocationManager().desiredAccuracy = newValue
        }
    }
    
    public var activityType: CLActivityType {
        get {
            return LocationTracker.sharedLocationManager().activityType
        }
        set {
            LocationTracker.sharedLocationManager().activityType = newValue
        }
    }
    
    var shareModel : LocationShareModel
    
    public var trackerConfig = LocationManagerConfig()
    
    public override init()  {
        self.shareModel = LocationShareModel()
        super.init()
        
        self.activityType = CLActivityType.OtherNavigation
        self.accuracy = kCLLocationAccuracyBestForNavigation
        self.distanceFilter = kCLDistanceFilterNone
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("applicationEnterBackground"), name: UIApplicationDidEnterBackgroundNotification, object: nil)
    }
    
    deinit {
         NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    public class func sharedLocationManager()-> CLLocationManager {
        
        struct Static {
            static var _locationManager : CLLocationManager?
        }
        
        objc_sync_enter(self)
        if Static._locationManager == nil {
            Static._locationManager = CLLocationManager()
            Static._locationManager!.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        }
        
        objc_sync_exit(self)
        return Static._locationManager!
    }
    
    // MARK: Application in background
    func applicationEnterBackground() {
        logger.debug("applicationEnterBackground")
        let locationManager = self.setupLocationManager()
        locationManager.startUpdatingLocation()
        
        self.shareModel.bgTask = BackgroundTaskManager.sharedBackgroundTaskManager()
        self.shareModel.bgTask?.beginNewBackgroundTask()
    }
    
    private func setupLocationManager() -> CLLocationManager {
        
        let locationManager : CLLocationManager = LocationTracker.sharedLocationManager()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
     
        locationManager.requestAlwaysAuthorization()
        
        if #available(iOS 9.0, *) {
            locationManager.allowsBackgroundLocationUpdates = true
        }
        
        return locationManager
    }
    
    func restartLocationUpdates() {
        logger.debug("restartLocationUpdates\n")
        
        if self.shareModel.timer != nil {
            self.shareModel.timer?.invalidate()
            self.shareModel.timer = nil
        }
        
        let locationManager = self.setupLocationManager()
        locationManager.startUpdatingLocation()
    }
    
   public  func startLocationTracking() {
        logger.debug("startLocationTracking\n")
        
        if CLLocationManager.locationServicesEnabled() == false {
            logger.debug("locationServicesEnabled false")
            
        } else {
            
            let authorizationStatus : CLAuthorizationStatus = CLLocationManager.authorizationStatus()
            if (authorizationStatus == CLAuthorizationStatus.Denied) || (authorizationStatus == CLAuthorizationStatus.Restricted) {
                logger.debug("authorizationStatus failed")
            } else {
                logger.debug("startLocationTracking authorized")
                let locationManager = self.setupLocationManager()
                locationManager.startUpdatingLocation()
            }
        }
    }
    
    public func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        logger.debug("locationManager didUpdateLocations\n")
        
       let goodLocations = locations.filter { (location) -> Bool in
        
            let locationAge : NSTimeInterval = location.timestamp.timeIntervalSinceNow
            if locationAge > 30.0 {
                return false
            }
        
            if (location.horizontalAccuracy > 0) && (location.horizontalAccuracy < 2000) && !((location.coordinate.latitude == 0.0) && (location.coordinate.longitude == 0.0)) {
                
                logger.debug("Good location with good accuracy \(location.coordinate.latitude) & \(location.coordinate.longitude)")
                
                return true
            }
        
            return false
        }
        
        var bestLocation: CLLocation?
        for location in goodLocations {
            let currentAccuracy = bestLocation?.horizontalAccuracy ?? 2000
            if location.horizontalAccuracy < currentAccuracy  {
                bestLocation = location
            }
        }
        
        if let newLocation = bestLocation {
            self.myLastLocation = newLocation;
            self.onLocationUpdate?(newLocation)
        }
        
        // If the timer still valid, return it (Will not run the code below)
        if self.shareModel.timer != nil {
            return
        }
        
        self.shareModel.bgTask = BackgroundTaskManager.sharedBackgroundTaskManager()
        self.shareModel.bgTask!.beginNewBackgroundTask()
        
        // Restart the locationManager after 1 minute
        let restartLocationUpdates : Selector = Selector("restartLocationUpdates")
        self.shareModel.timer = NSTimer.scheduledTimerWithTimeInterval(self.trackerConfig.sleepTimeBetweenSearches, target: self, selector: restartLocationUpdates, userInfo: nil, repeats: false)
        
        // Will only stop the locationManager after 10 seconds, so that we can get some accurate locations
        // The location manager will only operate for 10 seconds to save battery
        let stopLocationDelayBy10Seconds : Selector = Selector("stopLocationDelayBy10Seconds")
        var delay10Seconds : NSTimer = NSTimer.scheduledTimerWithTimeInterval(self.trackerConfig.locationSearchTime, target: self, selector: stopLocationDelayBy10Seconds, userInfo: nil, repeats: false)
    }
    
    //MARK: Stop the locationManager
     func stopLocationDelayBy10Seconds() {
        let locationManager : CLLocationManager = LocationTracker.sharedLocationManager()
        locationManager.stopUpdatingLocation()
        logger.debug("locationManager stop Updating after \(self.trackerConfig.locationSearchTime) seconds\n")
    }
    
    public func locationManager(manager: CLLocationManager, didFailWithError error: NSError) {
        
        logger.debug("locationManager Error: \(error.localizedDescription)")
            
        self.restartAfterMinutes(1)
        
    }
    
    func restartAfterMinutes(minutes : NSTimeInterval) -> Void {
        
        logger.debug("restartAfterMinutes \(minutes)")
        self.shareModel.bgTask = BackgroundTaskManager.sharedBackgroundTaskManager()
        self.shareModel.bgTask!.beginNewBackgroundTask()
        
        // Restart the locationManager after 1 minute
        let restartLocationUpdates : Selector = Selector("restartLocationUpdates")
        self.shareModel.timer = NSTimer.scheduledTimerWithTimeInterval(60 * minutes, target: self, selector: restartLocationUpdates, userInfo: nil, repeats: false)
    
    }
    
    public func stopLocationTracking () {
        logger.debug("stopLocationTracking\n")
        
        if self.shareModel.timer != nil {
            self.shareModel.timer!.invalidate()
            self.shareModel.timer = nil
        }
        let locationManager : CLLocationManager = LocationTracker.sharedLocationManager()
        locationManager.stopUpdatingLocation()
    }
    

}














