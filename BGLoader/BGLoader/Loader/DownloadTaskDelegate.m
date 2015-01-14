//
//  DownloadTaskDelegate.m
//  ProjectName
//
//  Created by Sergiy Suprun on 2/27/14.
//  Copyright (c) 2014 CompanyName. All rights reserved.
//

#import "DownloadTaskDelegate.h"

@interface  DownloadTaskDelegate() {
    SuccessHandler _successHandler;
    SuccessHandlerWithURL _successHandlerWithURL;
    FailHandler _failHandler;
    ProgressHandler _progressHandler;
}

@end

@implementation DownloadTaskDelegate

- (id)initWithTask:(NSURLSessionDownloadTask *)task
          success:(SuccessHandler)success
          failure:(FailHandler)failure
      andProgress:(ProgressHandler)progress {
    
    self = [super init];
    if (self) {
        _task = task;
        _successHandler = success;
        _failHandler = failure;
        _progressHandler = progress;
    }
    return self;
}

- (id)initWithTask:(NSURLSessionDownloadTask *)task
          successURL:(SuccessHandlerWithURL)success
          failure:(FailHandler)failure
      andProgress:(ProgressHandler)progress {
    
    self = [super init];
    if (self) {
        _task = task;
        _successHandlerWithURL = success;
        _failHandler = failure;
        _progressHandler = progress;
    }
    return self;
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes {
    if(_progressHandler) {
        _progressHandler((int)fileOffset, fileOffset, expectedTotalBytes);
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
didFinishDownloadingToURL:(NSURL *)location {

    if (_successHandler) {
        _successHandler([NSData dataWithContentsOfURL:location]);
    }
    else if (_successHandlerWithURL) {
        _successHandlerWithURL(location);
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    if(_progressHandler) {
        _progressHandler((int)bytesWritten, totalBytesWritten, totalBytesExpectedToWrite);
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error && _failHandler) {
        _failHandler(error);
    }
}

@end
