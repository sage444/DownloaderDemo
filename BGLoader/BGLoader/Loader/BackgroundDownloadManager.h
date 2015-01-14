//
//  BackgroundDownloadManager.h
//  ProjectName
//
//  Created by Sergiy Suprun on 2/27/14.
//  Copyright (c) 2014 CompanyName. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface BackgroundDownloadManager : NSObject

+ (BackgroundDownloadManager*)sharedManager;

- (void)downloadDataFromURL:(NSString*)url
                    success:(void (^)(NSData * responseData))success
                    failure:(void (^)(NSError *error))failure
                andProgress:(void(^)(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead))progress;

- (void)downloadDataFromURL:(NSString*)url
                 storeAtURL:(NSString*)destinationURL
                    success:(void (^)(NSData * responseData))success
                    failure:(void (^)(NSError *error))failure
                andProgress:(void(^)(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead))progress;

- (void)setBackgroundFetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler;

- (void)addCompletionHandler:(void (^)(void))completionHandler forSessionIdentifier:(NSString *)identifier;

- (void)invalidateSessionCancelingTasks:(BOOL)cancelPendingTasks;

- (void)callFetchCompletionHandler;

- (void)callFetchCompletionWithResult:(UIBackgroundFetchResult)fetchResult;


- (void)clearCache;

@end
 