//
//  DownloadTaskDelegate.h
//  ProjectName
//
//  Created by Sergiy Suprun on 2/27/14.
//  Copyright (c) 2014 CompanyName. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^SuccessHandlerWithURL)(NSURL * responseDataURL);
typedef void(^SuccessHandler)(NSData * responseData);
typedef void(^FailHandler)(NSError * error);
typedef void(^ProgressHandler)(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead);

@interface DownloadTaskDelegate : NSObject<NSURLSessionDownloadDelegate>

@property (nonatomic, weak) NSURLSessionDownloadTask * task;

- (id)initWithTask:(NSURLSessionDownloadTask *)task
          success:(SuccessHandler)success
          failure:(FailHandler)failure
      andProgress:(ProgressHandler)progress;

- (id)initWithTask:(NSURLSessionDownloadTask *)task
          successURL:(SuccessHandlerWithURL)success
          failure:(FailHandler)failure
      andProgress:(ProgressHandler)progress;

@end
