//
//  GridCell.swift
//  AVMedia Frame Picker
//
//  Created by Tuan Shou Cheng on 2017/12/8.
//  Copyright © 2017年 Tuan Shou Cheng. All rights reserved.
//

import UIKit

class GridCell: UICollectionViewCell {
    
    static let identifier: String = "Grid Cell"
    
    @IBOutlet weak var thumbnailImageView: UIImageView!
    
    var representedAssetIdentifier: String!

    var thumbnailImage: UIImage! {
        didSet {
            thumbnailImageView.image = thumbnailImage
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailImageView.image = nil
    }
}
