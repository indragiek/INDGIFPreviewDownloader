//
//  INDGIFPreviewDownloader.h
//  INDGIFPreviewDownloader
//
//  Created by Indragie on 10/28/14.
//  Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
//

#import <UIKit/UIKit.h>

/**
 *  Error domain for all errors produced by this class.
 */
extern NSString * const INDGIFPreviewDownloaderErrorDomain;

/**
 *  Error codes for errors encountered when reading the GIF file.
 */
typedef NS_ENUM(NSInteger, INDGIFErrorCode){
    /**
     *  There is insufficient data to extract an image
     *  from the file.
     */
    INDGIFErrorCodeInsufficientData = 1,
    /**
     *  The data is not in the expected format.
     */
    INDGIFErrorCodeMalformedData,
    /**
     *  Invalid GIF format signature (should be 'GIF')
     */
    INDGIFErrorCodeInvalidSignature,
    /**
     *  Invalid GIF version
     *
     *  87a and 89a are supported
     */
    INDGIFErrorCodeInvalidVersion,
    /**
     *  Unsupported block type.
     *
     *  Only image and extension blocks are supported
     */
    INDGIFErrorCodeUnsupportedBlock,
    /**
     *  Unsupported extension type.
     *
     *  Only application extensions, plain text extensions,
     *  comment extensions, and graphic control extensions
     *  are supported.
     */
    INDGIFErrorCodeUnsupportedExtension
};

/**
 Class that downloads only a single frame of a GIF file to create a preview
 image.
 */
@interface INDGIFPreviewDownloader : NSObject

/**
 *  Designated initializer.
 *
 *  @param configuration Configuration to use for the `NSURLSession` used
 *                       to download images.
 *
 *  @return An initialized instance of the receiver.
 */
- (instancetype)initWithURLSessionConfiguration:(NSURLSessionConfiguration *)configuration;

/**
 *  Downloads a single frame of a GIF image.
 *
 *  @param URL               The URL of the GIF image.
 *  @param completionQueue   Queue to call `completionHandler` on
 *  @param completionHandler Handler to be called upon success or error
 *
 *  @return The URL session task for the GIF download
 */
- (NSURLSessionTask *)downloadGIFPreviewFrameAtURL:(NSURL *)URL
                                   completionQueue:(dispatch_queue_t)completionQueue
                                 completionHandler:(void (^)(UIImage *, NSError *))completionHandler;

@end
