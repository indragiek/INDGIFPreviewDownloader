//
//  ViewController.swift
//  ExampleApp
//
//  Created by Indragie on 10/28/14.
//  Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    let downloader: INDGIFPreviewDownloader
    @IBOutlet var URLField: UITextField!
    @IBOutlet var imageView: UIImageView!

    required init(coder aDecoder: NSCoder) {
        downloader = INDGIFPreviewDownloader(URLSessionConfiguration: NSURLSessionConfiguration.defaultSessionConfiguration())
        super.init(coder: aDecoder)
    }
    
    @IBAction func download() {
        if let URLString = URLField.text {
            if let URL = NSURL(string: URLString) {
                downloader.downloadGIFPreviewFrameAtURL(URL, completionQueue: dispatch_get_main_queue()) { (image, error) in
                    self.imageView.image = image
                }
            }
        }
    }

}

