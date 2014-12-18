//
//  INDGIFPreviewDownloader.m
//  INDGIFPreviewDownloader
//
//  Created by Indragie on 10/28/14.
//  Copyright (c) 2014 Indragie Karunaratne. All rights reserved.
//

#import "INDGIFPreviewDownloader.h"

NSString * const INDGIFPreviewDownloaderErrorDomain = @"INDGIFPreviewDownloaderErrorDomain";

static NSError * GIFErrorWithCode(INDGIFErrorCode code, NSString *description)
{
    return [NSError errorWithDomain:INDGIFPreviewDownloaderErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey : description}];
}

static NSError * InsufficientDataError()
{
    return GIFErrorWithCode(INDGIFErrorCodeInsufficientData, @"Insufficient data to extract image");
}

// References:
// [0] http://www.w3.org/Graphics/GIF/spec-gif89a.txt
// [1] http://www.onicos.com/staff/iz/formats/gif.html
// [2] http://www.matthewflickinger.com/lab/whatsinagif/bits_and_bytes.asp

static BOOL VerifyGIFSignature(const uint8_t *bytes, NSUInteger *offset, NSError **error)
{
    // "GIF"
    BOOL valid = bytes[(*offset)++] == 'G' &&
                 bytes[(*offset)++] == 'I' &&
                 bytes[(*offset)++] == 'F';
    if (!valid && error) {
        *error = GIFErrorWithCode(INDGIFErrorCodeInvalidSignature, @"Invalid GIF signature");
    }
    return valid;
}

static BOOL VerifyGIFVersion(const uint8_t *bytes, NSUInteger *offset, NSError **error)
{
    // "87a" or "89a"
    BOOL valid = bytes[(*offset)++] == '8' &&
                 (bytes[*offset] == '7' || bytes[*offset] == '9') && (*offset)++ &&
                 bytes[(*offset)++] == 'a';
    if (!valid && error) {
        *error = GIFErrorWithCode(INDGIFErrorCodeInvalidVersion, @"Invalid GIF version");
    }
    return valid;
}

static void SkipGlobalColorTable(const uint8_t *bytes, NSUInteger *offset)
{
    const uint8_t packedFields = bytes[(*offset)++];
    const uint8_t gctFlag = packedFields >> 7;
    if (gctFlag) {
        const uint8_t n = packedFields & 0x7;
        *offset += (1 << (n + 1)) * 3; // # bytes = 2^(n+ 1) * 3
    }
}

static void SkipLocalColorTable(const uint8_t *bytes, NSUInteger *offset)
{
    const uint8_t packedFields = bytes[(*offset)++];
    const uint8_t lctFlag = packedFields >> 8;
    if (lctFlag) {
        const uint8_t n = packedFields & 0xf;
        *offset += (1 << (n + 1)) * 3; // # bytes = 2^(n+ 1) * 3
    }
}

static BOOL SkipBlockDataChunks(const uint8_t *bytes,
                                NSUInteger length,
                                NSUInteger *offset,
                                NSError **error)
{
    // Block Data
    // +---------------+
    // |   Block Size  |  0
    // |    (1 byte)   |
    // +---------------+
    // |   .. Data ..  |  1
    // +---------------+
    
    while (*offset < length) {
        const uint8_t blockHeader = bytes[(*offset)++];
        if (blockHeader) {
            *offset += blockHeader; // Block header is the block size
        } else { // Reached the end
            return YES;
        }
    }
    if (error) *error = InsufficientDataError();
    return NO;
}

static BOOL SkipApplicationExtensionBlock(const uint8_t *bytes,
                                          NSUInteger length,
                                          NSUInteger *offset,
                                          NSError **error)
{
    // Application Extension Block
    // +---------------+
    // |   Block Size  |  0
    // |    (1 byte)   |
    // +---------------+
    // |App Identifier |  1
    // |   (8 bytes)   |
    // +---------------+
    // |   Auth Code   |  9
    // |   (3 bytes)   |
    // +---------------+
    // |  .. Blocks .. |  12
    // +---------------+
    
    // Block size must be 0x0b
    if ((*offset >= length) || bytes[(*offset)++] != 0x0b) {
        if (error) *error = GIFErrorWithCode(INDGIFErrorCodeMalformedData, @"Application extension block has incorrect block size.");
        return NO;
    }
    *offset += 11; // Skip past Application Identifier and Auth Code
    return SkipBlockDataChunks(bytes, length, offset, error);
}

static BOOL SkipPlainTextExtensionBlock(const uint8_t *bytes,
                                        NSUInteger length,
                                        NSUInteger *offset,
                                        NSError **error)
{
    // Plain Text Extension Block
    // +---------------+
    // |   Block Size  |  0
    // |    (1 byte)   |
    // +---------------+
    // |Text Attributes|  1
    // |   (12 bytes)  |
    // +---------------+
    // |  .. Blocks .. |  13
    // +---------------+
    
    // Block size must be 0x0c
    if ((*offset >= length) || bytes[(*offset)++] != 0x0c) {
        if (error) *error = GIFErrorWithCode(INDGIFErrorCodeMalformedData, @"Plain text extension block has incorrect block size.");
        return NO;
    }
    *offset += 12; // Skip past text attributes
    return SkipBlockDataChunks(bytes, length, offset, error);
}

static BOOL SkipCommentExtensionBlock(const uint8_t *bytes,
                                      NSUInteger length,
                                      NSUInteger *offset,
                                      NSError **error)
{
    // Comment Extension Block
    // +---------------+
    // |  .. Blocks .. |  0
    // +---------------+
    return SkipBlockDataChunks(bytes, length, offset, error);
}

static BOOL SkipGraphicControlExtensionBlock(const uint8_t *bytes,
                                             NSUInteger length,
                                             NSUInteger *offset,
                                             NSError **error)
{
    // Graphic Control Extension Block
    // +---------------+
    // |   Block Size  |  0
    // |    (1 byte)   |
    // +---------------+
    // |   Attributes  |  1
    // |    (4 bytes)  |
    // +---------------+
    // |   Terminator  |  5
    // |    (1 byte)   |
    // +---------------+
    
    if (*offset + 6 >= length) {
        if (error) *error = InsufficientDataError();
        return NO;
    }
    
    // Block size must be 0x04
    if (bytes[(*offset)++] != 0x04) {
        if (error) *error = GIFErrorWithCode(INDGIFErrorCodeMalformedData, @"Graphic control extension block has incorrect block size.");
        return NO;
    }
    
    *offset += 4; // Skip attributes
    
    // Block terminator must be 0x00
    if (bytes[(*offset)++] != 0x00) {
        if (error) *error = GIFErrorWithCode(INDGIFErrorCodeMalformedData, @"Graphic control extension block has incorrect block terminator.");
        return NO;
    }
    
    return YES;
}

static NSData * GIFDataFromImageBlock(const uint8_t *bytes,
                                      NSUInteger length,
                                      NSUInteger *offset,
                                      NSError **error)
{
    // Image Block
    // +---------------+
    // |   Attributes  |  0
    // |    (8 bytes)  |
    // +---------------+
    // |  Packed Flags |  8
    // |0: LCTF        |
    // |1: Interlace   |
    // |2: Sort Flag   |
    // |2-3: Reserved  |
    // |4-7: LCT Size  |
    // |   (1 byte)    |
    // +---------------+
    // |      LCT      |  9
    // +---------------+
    // | LZW Min Size  |  10
    // |   (1 byte)    |
    // +---------------+
    // |  .. Blocks .. |  11
    // +---------------+
    if (*offset + 9 >= length) {
        if (error) *error = InsufficientDataError();
        return nil;
    }
    *offset += 8; // Skip attributes
    SkipLocalColorTable(bytes, offset);
    *offset += 1; // Skip LZW Minimum Code Size
    if (!SkipBlockDataChunks(bytes, length, offset, error)) {
        return nil;
    }
    
    NSMutableData *data = [NSMutableData dataWithBytes:bytes length:*offset];
    const uint8_t trailer = 0x3b;
    [data appendBytes:&trailer length:sizeof(uint8_t)];
    return data;
}

static UIImage * ExtractFirstGIFFrameInBuffer(NSData *buffer, NSError **error) {
    const uint8_t *bytes = (const uint8_t *)buffer.bytes;
    const NSUInteger length = buffer.length;
    NSUInteger offset = 0;
    
    // GIF Header
    // +---------------+
    // |     "GIF"     |  0
    // |   (3 bytes)   |
    // +---------------+
    // |    Version    |  3
    // | "87a" or "89a"|
    // |   (3 bytes)   |
    // +---------------+
    // | Screen Width  |  6
    // |   (2 bytes)   |
    // +---------------+
    // | Screen Height |  8
    // |   (2 bytes)   |
    // +---------------+
    // |  Packed Flags |  10
    // |0: GCTF        |
    // |1-3: Color Res |
    // |4: Sort Flag   |
    // |5-3: GCT Size  |
    // |   (1 byte)    |
    // +---------------+
    // |BG Color Index |  11
    // |   (1 byte)    |
    // +---------------+
    // |      GCT      |  12
    // +---------------+
    
    if (length < 13) {
        if (error) *error = InsufficientDataError();
        return nil;
    }
    
    if (!VerifyGIFSignature(bytes, &offset, error)) return nil;
    if (!VerifyGIFVersion(bytes, &offset, error)) return nil;
    
    
    offset += 4; // Skip Logical Screen Width and Logical Screen Height
    SkipGlobalColorTable(bytes, &offset);
    offset += 2; // Skip Background Color Index and Pixel Aspect Ratio
    
    while (offset < length) {
        switch (bytes[offset++]) {
            case 0x21:  // Extension Introducer
                if (offset >= length) {
                    if (error) *error = InsufficientDataError();
                    return nil;
                }
                switch (bytes[offset++]) {
                    case 0xff:
                        if (SkipApplicationExtensionBlock(bytes, length, &offset, error)) {
                            break;
                        } else {
                            return nil;
                        }
                    case 0x01:
                        if (SkipPlainTextExtensionBlock(bytes, length, &offset, error)) {
                            break;
                        } else {
                            return nil;
                        }
                    case 0xfe:
                        if (SkipCommentExtensionBlock(bytes, length, &offset, error)) {
                            break;
                        } else {
                            return nil;
                        }
                    case 0xf9:
                        if (SkipGraphicControlExtensionBlock(bytes, length, &offset, error)) {
                            break;
                        } else {
                            return nil;
                        }
                    default:
                        if (error) *error = GIFErrorWithCode(INDGIFErrorCodeUnsupportedExtension, @"Unsupported extension type");
                        return nil;
                }
                break;
            case 0x2c: { // Image Block
                NSData *data = GIFDataFromImageBlock(bytes, length, &offset, error);
                if (data != nil) {
                    return [UIImage imageWithData:data];
                } else {
                    break;
                }
            }
            default:
                if (error) *error = GIFErrorWithCode(INDGIFErrorCodeUnsupportedBlock, @"Unsupported block type");
                return nil;
        }
    }
    if (error) *error = InsufficientDataError();
    return nil;
}

@interface INDGIFPreviewTask : NSObject
@property (nonatomic, readonly) NSData *buffer;
@property (nonatomic, readonly) dispatch_queue_t completionQueue;
@property (nonatomic, copy, readonly) void (^completionHandler)(UIImage *, NSError *);
- (instancetype)initWithCompletionQueue:(dispatch_queue_t)completionQueue completionHandler:(void (^)(UIImage *, NSError *))completionHandler;
- (void)appendData:(NSData *)data;
@end

@implementation INDGIFPreviewTask {
    NSMutableData *_buffer;
}
@synthesize buffer = _buffer;

- (instancetype)initWithCompletionQueue:(dispatch_queue_t)completionQueue completionHandler:(void (^)(UIImage *, NSError *))completionHandler
{
    if ((self = [super init])) {
        _buffer = [[NSMutableData alloc] init];
        _completionQueue = completionQueue;
        _completionHandler = [completionHandler copy];
    }
    return self;
}

- (void)appendData:(NSData *)data
{
    [_buffer appendData:data];
}

@end

@interface INDGIFPreviewDownloader () <NSURLSessionDataDelegate>
@property (nonatomic, readonly) NSURLSession *session;
@property (nonatomic, readonly) NSOperationQueue *sessionQueue;
@property (nonatomic, readonly) dispatch_queue_t extractionQueue;
@property (nonatomic, readonly) dispatch_queue_t tasksQueue;
@property (nonatomic, readonly) NSMutableDictionary *tasks;
@end

@implementation INDGIFPreviewDownloader

- (instancetype)initWithURLSessionConfiguration:(NSURLSessionConfiguration *)configuration
{
    if ((self = [super init])) {
        _sessionQueue = [[NSOperationQueue alloc] init];
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:_sessionQueue];
        _extractionQueue = dispatch_queue_create("com.indragie.INDGIFPreviewDownloader.ExtractionQueue", DISPATCH_QUEUE_SERIAL);
        _tasksQueue = dispatch_queue_create("com.indragie.INDGIFPreviewDownloader.TasksQueue", DISPATCH_QUEUE_CONCURRENT);
        _tasks = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (NSURLSessionTask *)downloadGIFPreviewFrameAtURL:(NSURL *)URL
                                   completionQueue:(dispatch_queue_t)completionQueue
                                 completionHandler:(void (^)(UIImage *, NSError *))completionHandler
{
    NSParameterAssert(URL);
    NSParameterAssert(completionQueue);
    NSParameterAssert(completionHandler);
    
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    NSURLSessionTask *sessionTask = [self.session dataTaskWithRequest:request];
    INDGIFPreviewTask *previewTask = [[INDGIFPreviewTask alloc] initWithCompletionQueue:completionQueue completionHandler:completionHandler];
    [self setPreviewTask:previewTask forSessionTask:sessionTask];
    
    [sessionTask resume];
    return sessionTask;
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    dispatch_async(self.extractionQueue, ^{
        INDGIFPreviewTask *task = [self previewTaskForSessionTask:dataTask];
        if (task == nil) return;
        [task appendData:data];
        
        NSError *error = nil;
        UIImage *image = ExtractFirstGIFFrameInBuffer(task.buffer, &error);
        if (image != nil || (error != nil && error.code != INDGIFErrorCodeInsufficientData)) {
            [dataTask cancel];
            [self removePreviewTaskForSessionTask:dataTask];
            dispatch_async(task.completionQueue, ^{
                task.completionHandler(image, error);
            });
        }
    });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
didCompleteWithError:(NSError *)error
{
    dispatch_async(self.extractionQueue, ^{
        INDGIFPreviewTask *previewTask = [self previewTaskForSessionTask:task];
        if (previewTask == nil) return;
        
        dispatch_async(previewTask.completionQueue, ^{
            previewTask.completionHandler(nil, error ?: InsufficientDataError());
        });
        [self removePreviewTaskForSessionTask:task];
    });
}

#pragma mark - Private

- (void)setPreviewTask:(INDGIFPreviewTask *)previewTask forSessionTask:(NSURLSessionTask *)sessionTask
{
    dispatch_barrier_async(self.tasksQueue, ^{
        self.tasks[@(sessionTask.taskIdentifier)] = previewTask;
    });
}

- (INDGIFPreviewTask *)previewTaskForSessionTask:(NSURLSessionTask *)task
{
    __block INDGIFPreviewTask *previewTask = nil;
    dispatch_sync(self.tasksQueue, ^{
       previewTask = self.tasks[@(task.taskIdentifier)];
    });
    return previewTask;
}

- (void)removePreviewTaskForSessionTask:(NSURLSessionTask *)task
{
    dispatch_barrier_async(self.tasksQueue, ^{
        [self.tasks removeObjectForKey:@(task.taskIdentifier)];
    });
}

@end
