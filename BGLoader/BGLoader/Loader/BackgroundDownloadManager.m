//
//  BackgroundDownloadManager.m
//  ProjectName
//
//  Created by Sergiy Suprun on 2/27/14.
//  Copyright (c) 2014 CompanyName. All rights reserved.
//

#import "BackgroundDownloadManager.h"
#import "DownloadTaskDelegate.h"
#import "AppDelegate.h"

static NSString * BackgroundSessionIdenttificator = @"com.CompanyName.BackgroundSession";

NSString * const BackgroundDownloadManagerErrorDomain = @"com.CompanyName.BackgroundDownloadManager.error";


#define SERVICE_URL @"host.example.com"
#define USER_NAME @"user1"
#define USER_PASSWORD @"PassWORD"

static BackgroundDownloadManager * _sharedManager = nil;

static NSURLSession * _backgroundSession = nil;

typedef void (^BackgroundFetchCompleteHandler)(UIBackgroundFetchResult);

static dispatch_queue_t url_session_manager_creation_queue() {
    static dispatch_queue_t obi_url_session_manager_creation_queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        obi_url_session_manager_creation_queue = dispatch_queue_create("com.CompanyName.BackgroundDownloadManager.creation", DISPATCH_QUEUE_SERIAL);
    });
    
    return obi_url_session_manager_creation_queue;
}

@interface BackgroundDownloadManager () <NSURLSessionDelegate, NSURLSessionDownloadDelegate> {
    BackgroundFetchCompleteHandler _completionHandler;
    NSMutableDictionary * _taskList;
    NSMutableDictionary * _completedTask;
    NSMutableDictionary * _sessionCompletionHandlers;
    NSOperationQueue * _taskQueue;
    NSTimer * _watchDogTimer;
}

@end

@implementation BackgroundDownloadManager

+ (BackgroundDownloadManager*)sharedManager {
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        _sharedManager = [[self alloc] init];
    });
    
    return _sharedManager;
}

- (id)init {
    self = [super init];
    if (self) {
        _taskList = [NSMutableDictionary new];
        _completedTask = [NSMutableDictionary new];
        _taskQueue = [NSOperationQueue new];
        _taskQueue.maxConcurrentOperationCount = 1;
        _sessionCompletionHandlers = [NSMutableDictionary new];
        
        [self createCacheDirectoryIfNeed];
    }
    return self;
}

#pragma mark - Public methods

- (void)downloadDataFromURL:(NSString*)url
                    success:(void (^)(NSData * responseData))success
                    failure:(void (^)(NSError *error))failure
                andProgress:(void(^)(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead))progress {
    NSString * destinationURL = [self localFilePathForUrl:url];
    [self downloadDataFromURL:url
                   storeAtURL:destinationURL
                      success:success
                      failure:failure
                  andProgress:progress];
}

- (void)downloadDataFromURL:(NSString*)url
                 storeAtURL:(NSString*)destinationURL
                    success:(void (^)(NSData * responseData))success
                    failure:(void (^)(NSError *error))failure
                andProgress:(void(^)(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead))progress {
    
    NSString * escapedUrl = [url stringByReplacingOccurrencesOfString:@"'" withString:@"%27"];
    
    NSData * data = [self localDataForUrl:url];
        if(data) {
            if(success) {
                success(data);
            }
        }
        else {
            NSURL * downloadUrl = [NSURL URLWithString:escapedUrl];
           
            __block NSURLSessionDownloadTask *downloadTask = nil;
            dispatch_sync(url_session_manager_creation_queue(), ^{
                downloadTask = [self.backgroundSession downloadTaskWithURL:downloadUrl];
            });
            
            if (!downloadTask) {
                [self reinitUrlSession];
                
                dispatch_sync(url_session_manager_creation_queue(), ^{
                    downloadTask = [self.backgroundSession downloadTaskWithURL:downloadUrl];
                });
                
                if (!downloadTask) {
                    NSString * errorFormat = @"Failed create download task for session: %@, download task for url: '%@'";
                    NSString * errorDescription = [NSString stringWithFormat:errorFormat, self.backgroundSession, downloadUrl];
                    
                    if (failure)  {
                        NSError * error = nil;
                        error = [NSError errorWithDomain:BackgroundDownloadManagerErrorDomain
                                                                                    code:0
                                                                                userInfo:@{ NSLocalizedDescriptionKey: errorDescription}];
                        failure(error);
                    }
                }
            }
            
            if (downloadTask) {
                DownloadTaskDelegate * delegate = [[DownloadTaskDelegate alloc] initWithTask:downloadTask successURL:^(NSURL *responseDataURL) {
                    if(responseDataURL) {
                        NSError * error = nil;
                        [self saveFileFromUrl:responseDataURL
                                   toLocalPath:destinationURL
                                        error:&error];
                        
                        NSData * fileData = nil;
                        if (!error) {
                            fileData = [NSData dataWithContentsOfFile:destinationURL
                                                              options:NSDataReadingMappedAlways
                                                                error:&error];
                            if (!error && fileData)  {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    success(fileData);
                                });
                            }
                        }
                        
                        if (error && failure)  {
                            failure(error);
                        }
                    }
                } failure:^(NSError *error) {
                    if (failure) {
                        failure(error);
                    }
                } andProgress:^(NSUInteger bytesRead, long long totalBytesRead, long long totalBytesExpectedToRead) {
                    if(progress) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            progress(bytesRead, totalBytesRead, totalBytesExpectedToRead);
                        });
                    }
                }];
                
                [_taskList setObject:delegate forKey:downloadTask];
                [downloadTask resume];
            }
        }
}

- (void)setBackgroundFetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler {
    _completionHandler = completionHandler;
    
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        if (_watchDogTimer) {
            [_watchDogTimer invalidate];
            _watchDogTimer = nil;
        }
        
        _watchDogTimer = [NSTimer scheduledTimerWithTimeInterval:[UIApplication sharedApplication].backgroundTimeRemaining - 1.0
                                                          target:self
                                                        selector:@selector(checkBackroundTime:)
                                                        userInfo:nil
                                                         repeats:NO];
    }
}

- (void)addCompletionHandler:(void (^)(void))completionHandler forSessionIdentifier:(NSString *)identifier {
    if ([_sessionCompletionHandlers objectForKey:identifier]) {
        NSLog(@"Error: Got multiple handlers for a single session identifier. This should not happen.");
    }
    [_sessionCompletionHandlers setObject:[completionHandler copy] forKey:identifier];
}

- (void)invalidateSessionCancelingTasks:(BOOL)cancelPendingTasks {
    if (cancelPendingTasks) {
        [self.backgroundSession invalidateAndCancel];
    } else {
        [self.backgroundSession finishTasksAndInvalidate];
    }
}

- (void)callFetchCompletionHandler {
    [self callFetchCompletionWithResult:_completedTask.count > 0 ? UIBackgroundFetchResultNewData : UIBackgroundFetchResultNoData];
}

- (void)callFetchCompletionWithResult:(UIBackgroundFetchResult)fetchResult {
    if (_completionHandler) {
        _completionHandler(fetchResult);
        _completionHandler = nil;
    }
}

#pragma mark - Watchdog timer

- (void)checkBackroundTime:(NSTimer *)timer {
    [_watchDogTimer invalidate];
    _watchDogTimer = nil;
    
    NSLog(@"background fetch interupted due timeout");
    [self callFetchCompletionHandler];
}

#pragma mark - Download delegate

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes {
    NSLog(@"%s", __PRETTY_FUNCTION__);
    DownloadTaskDelegate * taskDelegate = nil;
    taskDelegate = [self getDelegateForTask:downloadTask];
    if (taskDelegate) {
        [taskDelegate URLSession:session
                    downloadTask:downloadTask
               didResumeAtOffset:fileOffset
              expectedTotalBytes:expectedTotalBytes];
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    DownloadTaskDelegate * taskDelegate = [self getDelegateForTask:downloadTask];
    
    if (taskDelegate) {
        [taskDelegate URLSession:session downloadTask:downloadTask didFinishDownloadingToURL:location];
        [_taskList removeObjectForKey:downloadTask];
        [_completedTask setObject:taskDelegate forKey:downloadTask];
        
        if (_taskList.count == 0) {
            BOOL hasNewData = ([_completedTask count] > 0);
            [_taskList removeAllObjects];
            [_completedTask removeAllObjects];
            [self callFetchCompletionWithResult:(hasNewData) ? UIBackgroundFetchResultNewData : UIBackgroundFetchResultNoData];
        }
    }
}

- (void)URLSession:(NSURLSession *)session
      downloadTask:(NSURLSessionDownloadTask *)downloadTask
      didWriteData:(int64_t)bytesWritten
 totalBytesWritten:(int64_t)totalBytesWritten
totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    DownloadTaskDelegate * taskDelegate = [self getDelegateForTask:downloadTask];
    
    if (taskDelegate) {
        [taskDelegate URLSession:session
                    downloadTask:downloadTask
                    didWriteData:bytesWritten
               totalBytesWritten:totalBytesWritten
       totalBytesExpectedToWrite:totalBytesExpectedToWrite];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (error) {
        NSLog(@"task error: %@", error.localizedDescription);
        NSLog(@"url %@", task.response.URL);

        DownloadTaskDelegate * taskDelegate = [self getDelegateForTask:task];
        
        if (taskDelegate) {
            [taskDelegate URLSession:(NSURLSession *)session task:task didCompleteWithError:error];
            [_completedTask setObject:taskDelegate forKey:task];
        }
        
        [_taskList removeObjectForKey:task];
    }
}

#pragma mark - NSURlSessionDelegate

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    if(error) {
        NSLog(@"error in session: %@", error.localizedDescription);
    }
    [self reinitUrlSession];
}

- (void)URLSession:(NSURLSession *)session
didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge
 completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    NSURL * serviceUrl = [NSURL URLWithString:SERVICE_URL];
    NSURLCredential * credential = nil;
    if ([challenge.protectionSpace.host isEqualToString:serviceUrl.host]) {
        credential = [NSURLCredential credentialWithUser:USER_NAME
                                                password:USER_PASSWORD
                                             persistence:NSURLCredentialPersistenceForSession];
    }
    else {
       credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
    }
    
    completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    if (session.configuration.identifier) {
        [self callCompletionHandlerForSession:session.configuration.identifier];
    }
}

#pragma mark - Private methods

- (DownloadTaskDelegate *)getDelegateForTask:(NSURLSessionTask*)task {
    DownloadTaskDelegate * taskDelegate = [_taskList objectForKey:task];
    return taskDelegate;
}

- (void)callCompletionHandlerForSession:(NSString *)sessionIdentifier {
    void (^compleationHandler)(void) = [_sessionCompletionHandlers objectForKey:sessionIdentifier];
    
    if (compleationHandler) {
        [_sessionCompletionHandlers removeObjectForKey:compleationHandler];
        compleationHandler();
    }
}

- (NSURLSession*)backgroundSession {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:BackgroundSessionIdenttificator];
        _backgroundSession = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:nil];
    });
    return _backgroundSession;
}

- (void)reinitUrlSession {
    if (_backgroundSession) {
        [_backgroundSession resetWithCompletionHandler:^{
            _backgroundSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:BackgroundSessionIdenttificator]
                                                               delegate:self
                                                          delegateQueue:_taskQueue];
        }];
    }
}

- (void)createCacheDirectoryIfNeed {
    NSArray  * paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString * cacheDirectory = [paths objectAtIndex:0];
    NSError * err = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[cacheDirectory stringByAppendingPathComponent:@"com.apple.nsnetworkd"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&err];
    if (err) {
        NSLog(@"%s error: %@",__PRETTY_FUNCTION__, err.localizedDescription);
    }
}

- (NSError*)downloadError {
    NSError * downloadError = [NSError errorWithDomain:BackgroundDownloadManagerErrorDomain
                                                  code:0
                                              userInfo:@{ NSLocalizedDescriptionKey: @"Download failed"}];
    return downloadError;
}


#pragma mark - local file store

-(NSString *)cacheDirectory
{
    NSArray *myPathList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachePath    = [myPathList  objectAtIndex:0];
    

    
    cachePath = [cachePath stringByAppendingPathComponent:NSStringFromClass([self class])];

    return cachePath;
}

-(NSString*)localFilePathForUrl:(NSString*)url {
    NSString *cachePath = [self cacheDirectory];
    NSFileManager * fm = [NSFileManager new];
    
    [fm createDirectoryAtPath:cachePath
  withIntermediateDirectories:YES
                   attributes:nil
                        error:nil];
    
    NSString * hashAndExt = [NSString stringWithFormat:@"%@.%@",url.sha1, url.pathExtension];
    
    NSString * fullPath = [cachePath stringByAppendingPathComponent:hashAndExt];
    
    return fullPath;
}

-(NSData *)localDataForUrl:(NSString *)url {
    NSFileManager * fm = [NSFileManager new];
    
    NSString * localPath =  [self localFilePathForUrl:url];
    
    if ([fm fileExistsAtPath:localPath]) {
        NSError * err = nil;
        NSData * data = [NSData dataWithContentsOfFile:localPath options:NSDataReadingMapped error:&err];
        if (data && !err) {
            return data;
        }
    }
        return nil;
}

-(BOOL)saveFileFromUrl:(NSURL*)sourceURL toLocalPath:(NSString*)localPath error:(NSError**)err{
    NSFileManager * fm = [NSFileManager new];
    NSURL * localUrl = [NSURL fileURLWithPath:localPath];
    [fm moveItemAtURL:sourceURL toURL:localUrl error:err];
    return err == nil;
}


- (void)clearCache {
    NSFileManager * fm = [NSFileManager new];
    [fm removeItemAtPath:[self cacheDirectory] error:nil];
}

@end
