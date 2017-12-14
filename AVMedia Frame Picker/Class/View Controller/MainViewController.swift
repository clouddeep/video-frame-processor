//
//  ViewController.swift
//  AVMedia Frame Picker
//
//  Created by Tuan Shou Cheng on 2017/12/8.
//  Copyright © 2017年 Tuan Shou Cheng. All rights reserved.
//

import UIKit
import Photos

class MainViewController: UIViewController {
    
    @IBOutlet weak var collectionView: UICollectionView!
    
    var allVideo: PHFetchResult<PHAsset>!
    
    fileprivate let imageManager = PHCachingImageManager()
    fileprivate var thumbnailSize: CGSize = CGSize.zero
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let allMediaOptions = PHFetchOptions()
        allMediaOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        
        allVideo = PHAsset.fetchAssets(with: .video, options: allMediaOptions)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let screenWidth = UIScreen.main.bounds.size.width
        thumbnailSize = CGSize(width: screenWidth/2.0 - 10, height: screenWidth/2.0 - 10)
        
        collectionView.reloadData()
    }
    
    @IBAction func setupAngle(_ sender: UIBarButtonItem) {
        presentAngleChangeAlert()
    }
    
    fileprivate func presentAngleChangeAlert() {
        let alert = UIAlertController(title: "Change angle", message: nil, preferredStyle: .alert)
        alert.addTextField { (textField) in
            textField.keyboardType = .numberPad
            textField.placeholder = "Enter new angle"

            if let angle = AFPProfile.angle {
                textField.text = String(angle)
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        let confirmAction = UIAlertAction(title: "OK", style: .default) { (action) in
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            
            if let text = alert.textFields?.first?.text,
                let value = numberFormatter.number(from: text) {
                print("enter value is \(value.floatValue)")
                AFPProfile.angle = value.floatValue
            }
        }
        
        alert.addAction(confirmAction)
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
}

extension MainViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let vc = VideoFrameViewController()
        let nc = AFPNavigationController(rootViewController: vc)
        vc.photoAsset = allVideo.object(at: indexPath.item)
        
        present(nc, animated: true, completion: nil)
//        navigationController?.pushViewController(nc, animated: true)
        
        collectionView.deselectItem(at: indexPath, animated: true)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return thumbnailSize
    }
}

extension MainViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return allVideo.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: GridCell.identifier, for: indexPath) as? GridCell else { fatalError("unexpected cell in collection view") }
        
        let videoAsset = allVideo.object(at: indexPath.item)
        
        cell.representedAssetIdentifier = videoAsset.localIdentifier
        imageManager.requestImage(for: videoAsset, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil, resultHandler: { image, _ in
            // The cell may have been recycled by the time this handler gets called;
            // set the cell's thumbnail image only if it's still showing the same asset.
            if cell.representedAssetIdentifier == videoAsset.localIdentifier {
                cell.thumbnailImage = image
            }
        })
        
        return cell
    }
}

extension MainViewController {
    override var shouldAutorotate: Bool {
        return false
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
}
