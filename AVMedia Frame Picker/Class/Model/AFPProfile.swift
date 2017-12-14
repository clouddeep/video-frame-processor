//
//  AFPProfile.swift
//  AVMedia Frame Picker
//
//  Created by Tuan Shou Cheng on 2017/12/9.
//  Copyright © 2017年 Tuan Shou Cheng. All rights reserved.
//

import UIKit

class AFPProfile: NSObject {
    static var angle: Float? {
        get {
            let value = UserDefaults.standard.float(forKey: "angle")
            return value
        }
        
        set {
            UserDefaults.standard.set(newValue, forKey: "angle")
            UserDefaults.standard.synchronize()
        }
    }

}
