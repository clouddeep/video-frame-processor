//
//  VideoFrameViewController.swift
//  AVMedia Frame Picker
//
//  Created by Tuan Shou Cheng on 2017/12/8.
//  Copyright © 2017年 Tuan Shou Cheng. All rights reserved.
//

import UIKit
import Photos
import AVKit

enum CyanifyError: Error {
    case NoMediaData
}

class VideoFrameViewController: UIViewController {
    
    var photoAsset: PHAsset?
    
    var converter: VideoConverter?
    
    let playerViewController = AVPlayerViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationController?.setNavigationBarHidden(true, animated: false)
        
        converter = VideoConverter(asset: photoAsset!, completion: { [weak self] (completion, asset, error) in
            if completion {
                self?.play(asset: asset!)
            } else {
                print("load false")
            }
        })
        
        // Set frame processor here
        // sampleBuffer is type of CMSampleBuffer
        converter?.frameProcess = { (sampleBuffer) in
            // do something like:
            // processFrame(sampleBuffer)
        }
        
        converter!.startLoadAsset()
        
        self.addChildViewController(playerViewController)
        self.view.addSubview(playerViewController.view)
        playerViewController.didMove(toParentViewController: self)
        
        playerViewController.view.frame = view.bounds
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        converter!.processState = .cancelled
    }
    
    @objc func dismissVideo(_ sender: UIBarButtonItem) {
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
    
    // MARK:- Play
    
    func play(asset: AVAsset) {
        let playerItem = AVPlayerItem(asset: asset)
        playerViewController.player = AVPlayer(playerItem: playerItem)
    }
    
    
    // Play PHAsset directly
    func play(photoAsset: PHAsset) {
        PHImageManager.default().requestPlayerItem(forVideo: photoAsset, options: nil) { [weak self] (playerItem, info) in
            self?.playerViewController.player = AVPlayer(playerItem: playerItem)
        }
    }
    
}

extension VideoFrameViewController {
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeLeft
    }
}
