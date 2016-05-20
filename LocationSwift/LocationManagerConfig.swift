//
//  LocationManagerConfig.swift
//  LocationSwift
//
//  Created by Błażej Szajrych on 20.05.2016.
//  Copyright © 2016 Emerson Carvalho. All rights reserved.
//

import Foundation

public struct LocationManagerConfig {
    
    public init() {
    }
    
    public var locationSearchTime: NSTimeInterval = 4.0
    public var sleepTimeBetweenSearches: NSTimeInterval = 60.0
}
