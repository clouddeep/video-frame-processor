//
//  AFPNavigationController.swift
//  AVMedia Frame Picker
//
//  Created by Tuan Shou Cheng on 2017/12/12.
//  Copyright © 2017年 Tuan Shou Cheng. All rights reserved.
//

import UIKit

class AFPNavigationController: UINavigationController {
    
    override var shouldAutorotate: Bool {
        return visibleViewController?.shouldAutorotate ?? true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return visibleViewController?.supportedInterfaceOrientations ?? .portrait
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return visibleViewController?.preferredInterfaceOrientationForPresentation ?? .portrait
    }
}
