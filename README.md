## INDGIFPreviewDownloader

`INDGIFPreviewDownloader` retrieves preview images for animated GIF files by downloading only the first frame. Compared to downloading the entire GIF file to create a preview image, this solution saves a huge amount of bandwidth.

Try it out using the included example app!

### Usage

#### Objective-C

```objective-c
self.downloader = [[INDGIFPreviewDownloader alloc] initWithURLSessionConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
[self.downloader downloadGIFPreviewFrameAtURL:[NSURL URLWithString:@"http://i.imgur.com/irqjHqT.gif"] completionQueue:dispatch_get_main_queue() completionHandler:^(UIImage *image, NSError *error) {
    self.imageView.image = image;
}];
```

#### Swift

```swift
downloader = INDGIFPreviewDownloader(URLSessionConfiguration: NSURLSessionConfiguration.defaultSessionConfiguration())
downloader.downloadGIFPreviewFrameAtURL(NSURL(string: "http://i.imgur.com/irqjHqT.gif")!, completionQueue: dispatch_get_main_queue()) { (image, error) in
    self.imageView.image = image
}
```

### How it Works

`INDGIFPreviewDownloader` initiates a download of the raw GIF data and attempts to find a complete image data block (in accordance with the [GIF spec](http://www.w3.org/Graphics/GIF/spec-gif89a.txt)) every time new data is received. Once enough data is available to extract an image, the download is cancelled. 

### Contact

* Indragie Karunaratne
* [@indragie](http://twitter.com/indragie)
* [http://indragie.com](http://indragie.com)

### License

`INDGIFPreviewDownloader` is licensed under the MIT License.

