/*
 
 Copyright (C) 2011 GUI Cocoa, LLC.
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 
 */

#import "EBNotice.h"
#import "EBNotifierFunctions.h"

#import "EBNotifier.h"

#if TARGET_OS_IPHONE
#import "GCAlertView.h"
#endif

// internal
static SCNetworkReachabilityRef __reachability = nil;
static id<EBNotifierDelegate> __delegate = nil;
static NSMutableDictionary * __userData;
static NSString * __APIKey    = nil;
static BOOL __useSSL          = NO;
static BOOL __displayPrompt   = YES;
static NSString * __hostName  = nil;

// constant strings
static NSString * const EBNotifierAlwaysSendKey             = @"AlwaysSendCrashReports";
NSString * const EBNotifierWillDisplayAlertNotification     = @"EBNotifierWillDisplayAlert";
NSString * const EBNotifierDidDismissAlertNotification      = @"EBNotifierDidDismissAlert";
NSString * const EBNotifierWillPostNoticesNotification      = @"EBNotifierWillPostNotices";
NSString * const EBNotifierDidPostNoticesNotification       = @"EBNotifierDidPostNotices";
NSString * const EBNotifierVersion                          = @"3.2";
NSString * const EBNotifierDevelopmentEnvironment           = @"Development";
NSString * const EBNotifierAdHocEnvironment                 = @"Ad Hoc";
NSString * const EBNotifierAppStoreEnvironment              = @"App Store";
NSString * const EBNotifierReleaseEnvironment               = @"Release";
#if defined (DEBUG) || defined (DEVELOPMENT)
NSString * const EBNotifierAutomaticEnvironment             = @"Development";
#elif defined (TEST) || defined (TESTING)
NSString * const EBNotifierAutomaticEnvironment             = @"Test";
#else
NSString * const EBNotifierAutomaticEnvironment             = @"Production";
#endif

// reachability callback
void EBNotifierReachabilityDidChange(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info);

@interface EBNotifier ()

// get the path where notices are stored
+ (NSString *)pathForNoticesDirectory;

// get the path for a new notice given the file name
+ (NSString *)pathForNewNoticeWithName:(NSString *)name;

// get the paths for all valid notices
+ (NSArray *)pathsForAllNotices;

// post all provided notices to airbrake
+ (void)postNoticesWithPaths:(NSArray *)paths;

// post the given notice to the given URL
+ (void)postNoticeWithContentsOfFile:(NSString *)path toURL:(NSURL *)URL;

// caches user data to store that can be read at signal time
+ (void)cacheUserDataDictionary;

// pop a notice alert and perform necessary actions
+ (void)showNoticeAlertForNoticesWithPaths:(NSArray *)paths;

// determine if we are reachable with given flags
+ (BOOL)isReachable:(SCNetworkReachabilityFlags)flags;

@end

@implementation EBNotifier

#pragma mark - initialize the notifier
+ (void)startNotifierWithAPIKey:(NSString *)key
                  serverAddress:(NSString *)server
                environmentName:(NSString *)name
                         useSSL:(BOOL)useSSL
                       delegate:(id<EBNotifierDelegate>)delegate {

  [self startNotifierWithAPIKey:key
                  serverAddress:(NSString *)server
                environmentName:name
                         useSSL:useSSL
                       delegate:delegate
        installExceptionHandler:YES
           installSignalHandler:YES
              displayUserPrompt:YES];
}

+ (void)startNotifierWithAPIKey:(NSString *)key
                  serverAddress:(NSString *)server
                environmentName:(NSString *)name
                         useSSL:(BOOL)useSSL
                       delegate:(id<EBNotifierDelegate>)delegate
        installExceptionHandler:(BOOL)exception
           installSignalHandler:(BOOL)signal {

  [self startNotifierWithAPIKey:key
                  serverAddress:(NSString *)server
                environmentName:name
                         useSSL:useSSL
                       delegate:delegate
        installExceptionHandler:exception
           installSignalHandler:signal
              displayUserPrompt:YES];
}

+ (void)startNotifierWithAPIKey:(NSString *)key
                  serverAddress:(NSString *)server
                environmentName:(NSString *)name
                         useSSL:(BOOL)useSSL
                       delegate:(id<EBNotifierDelegate>)delegate
        installExceptionHandler:(BOOL)exception
           installSignalHandler:(BOOL)signal
              displayUserPrompt:(BOOL)display {
  @synchronized(self) {
    static BOOL token = YES;
    if (token) {

      // change token5
      token = NO;

      // register defaults
      [[NSUserDefaults standardUserDefaults] registerDefaults:
                   [NSDictionary dictionaryWithObject:@"NO" forKey:EBNotifierAlwaysSendKey]];

      // capture vars
      __userData = [[NSMutableDictionary alloc] init];
      __delegate = delegate;
      __useSSL = useSSL;
      __displayPrompt = display;
      __hostName = server;

      // switch on api key
      if ([key length]) {
        __APIKey = [key copy];
        __reachability = SCNetworkReachabilityCreateWithName(NULL, [__hostName UTF8String]);
        if (SCNetworkReachabilitySetCallback(__reachability, EBNotifierReachabilityDidChange, nil)) {
          if (!SCNetworkReachabilityScheduleWithRunLoop(__reachability, CFRunLoopGetMain(), kCFRunLoopDefaultMode)) {
            EBLog(@"Reachability could not be configired. No notices will be posted.");
          }
        }
      } else {
        EBLog(@"The API key must not be blank. No notices will be posted.");
      }

      // switch on environment name
      if ([name length]) {

        // vars
        unsigned long length;

        // cache signal notice file path
        NSString *fileName = [[NSProcessInfo processInfo] globallyUniqueString];
        const char *filePath = [[EBNotifier pathForNewNoticeWithName:fileName] UTF8String];
        length = (strlen(filePath) + 1);
        eb_signal_info.notice_path = malloc(length);
        memcpy((void *)eb_signal_info.notice_path, filePath, length);

        // cache notice payload
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:
                          [NSDictionary dictionaryWithObjectsAndKeys: name, EBNotifierEnvironmentNameKey,
                               [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
                                 EBNotifierBundleVersionKey,
                                 [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleExecutable"],
                                 EBNotifierExecutableKey,
                                 nil]];
        length = [data length];
        eb_signal_info.notice_payload = malloc(length);
        memcpy(eb_signal_info.notice_payload, [data bytes], length);
        eb_signal_info.notice_payload_length = length;

        // cache user data
        [self addEnvironmentEntriesFromDictionary:
             [NSMutableDictionary dictionaryWithObjectsAndKeys:
              EBNotifierPlatformName(), EBNotifierPlatformNameKey,
              EBNotifierOperatingSystemVersion(), EBNotifierOperatingSystemVersionKey,
              EBNotifierApplicationVersion(), EBNotifierApplicationVersionKey,
              nil]];

        // start handlers
        if (exception) {
          EBNotifierStartExceptionHandler();
        }

        if (signal) {
          EBNotifierStartSignalHandler();
        }

        // log
        EBLog(@"Notifier %@ ready to catch errors", EBNotifierVersion);
        EBLog(@"Environment \"%@\"", name);

      } else {
        EBLog(@"The environment name must not be blank. No new notices will be logged");
      }
    }
  }
}

#pragma mark - accessors
+ (id<EBNotifierDelegate>)delegate {
  @synchronized(self) {
    return __delegate;
  }
}

+ (NSString *)APIKey {
  @synchronized(self) {
    return __APIKey;
  }
}

#pragma mark - write data
+ (void)logException:(NSException *)exception parameters:(NSDictionary *)parameters {
    
  // force all activity onto main thread
  if (![NSThread isMainThread]) {
    dispatch_sync(dispatch_get_main_queue(), ^{
      [self logException:exception parameters:parameters];
    });
    return;
  }
    
  // get file handle
  NSString *name = [[NSProcessInfo processInfo] globallyUniqueString];
  NSString *path = [self pathForNewNoticeWithName:name];
  int fd = EBNotifierOpenNewNoticeFile([path UTF8String], EBNotifierExceptionNoticeType);
    
  // write stuff
  if (fd > -1) {
    @try {

      // create parameters
      NSMutableDictionary *exceptionParameters = [NSMutableDictionary dictionary];
      if ([parameters count]) {
        [exceptionParameters addEntriesFromDictionary:parameters];
      }

      [exceptionParameters setValue:EBNotifierResidentMemoryUsage()
                             forKey:@"Resident Memory Size"];

      [exceptionParameters setValue:EBNotifierVirtualMemoryUsage()
                             forKey:@"Virtual Memory Size"];

      // write exception
      NSDictionary *dictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [exception name], EBNotifierExceptionNameKey,
                                    [exception reason], EBNotifierExceptionReasonKey,
                                    [exception callStackSymbols], EBNotifierCallStackKey,
                                    exceptionParameters, EBNotifierExceptionParametersKey,
#if TARGET_OS_IPHONE
                                    EBNotifierCurrentViewController(), EBNotifierControllerKey,
#endif
                                    nil];

      NSData *data = [NSKeyedArchiver archivedDataWithRootObject:dictionary];
      unsigned long length = [data length];
      write(fd, &length, sizeof(unsigned long));
      write(fd, [data bytes], length);

      // delegate
      id<EBNotifierDelegate> delegate = [self delegate];

      if ([delegate respondsToSelector:@selector(notifierDidLogException:)]) {
        [delegate notifierDidLogException:exception];
      }

    }
    @catch (NSException *exception) {
      EBLog(@"Exception encountered while logging exception");
      EBLog(@"%@", exception);
    }
    @finally {
      close(fd);
    }
  } else {
    EBLog(@"Error reading notice file: %@", path);
  }
}

+ (void)logException:(NSException *)exception {
  [self logException:exception parameters:nil];
}

+ (void)writeTestNotice {
  @try {
    NSArray *array = [NSArray array];
    [array objectAtIndex:NSUIntegerMax];
  }
  @catch (NSException *e) {
    [self logException:e];
  }
}

#pragma mark - environment variables
+ (void)setEnvironmentValue:(NSString *)value forKey:(NSString *)key {
  @synchronized(self) {
    [__userData setObject:value forKey:key];
    [EBNotifier cacheUserDataDictionary];
  }
}

+ (void)addEnvironmentEntriesFromDictionary:(NSDictionary *)dictionary {
  @synchronized(self) {
    [__userData addEntriesFromDictionary:dictionary];
    [EBNotifier cacheUserDataDictionary];
  }
}

+ (NSString *)environmentValueForKey:(NSString *)key {
  @synchronized(self) {
    return [__userData objectForKey:key];
  }
}

+ (void)removeEnvironmentValueForKey:(NSString *)key {
  @synchronized(self) {
    [__userData removeObjectForKey:key];
    [EBNotifier cacheUserDataDictionary];
  }
}

+ (void)removeEnvironmentValuesForKeys:(NSArray *)keys {
  @synchronized(self) {
    [__userData removeObjectsForKeys:keys];
    [EBNotifier cacheUserDataDictionary];
  }
}

#pragma mark - file utilities
+ (NSString *)pathForNoticesDirectory {
  static NSString *path = nil;
  static dispatch_once_t token;

  dispatch_once(&token, ^{
#if TARGET_OS_IPHONE
    NSArray *folders = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    path = [folders objectAtIndex:0];
    if ([folders count] == 0) {
      path = NSTemporaryDirectory();
    } else {
      path = [path stringByAppendingPathComponent:@"Errbit Notices"];
    }
#else
    NSArray *folders = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    path = [folders objectAtIndex:0];
    if ([folders count] == 0) {
        path = NSTemporaryDirectory();
    }
    else {
        path = [path stringByAppendingPathComponent:EBNotifierApplicationName()];
        path = [path stringByAppendingPathComponent:@"Errbit Notices"];
    }
#endif
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager fileExistsAtPath:path]) {
      [manager createDirectoryAtPath:path
         withIntermediateDirectories:YES
                          attributes:nil
                               error:nil];
    }

    [path retain];
  });

  return path;
}

+ (NSString *)pathForNewNoticeWithName:(NSString *)name {
  NSString *path = [self pathForNoticesDirectory];
  path = [path stringByAppendingPathComponent:name];
  return [path stringByAppendingPathExtension:EBNotifierNoticePathExtension];
}

+ (NSArray *)pathsForAllNotices {
  NSString *path = [self pathForNoticesDirectory];
  NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:nil];
  NSMutableArray *paths = [NSMutableArray arrayWithCapacity:[contents count]];
  [contents enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    if ([[obj pathExtension] isEqualToString:EBNotifierNoticePathExtension]) {
      NSString *noticePath = [path stringByAppendingPathComponent:obj];
      [paths addObject:noticePath];
    }
  }];
  return paths;
}

#pragma mark - post notices
+ (void)postNoticesWithPaths:(NSArray *)paths {
    
  // assert
  NSAssert(![NSThread isMainThread], @"This method must not be called on the main thread");
  NSAssert([paths count], @"No paths were provided");
    
  // get variables
  if ([paths count] == 0) { return; }
  id<EBNotifierDelegate> delegate = [EBNotifier delegate];
    
  // notify people
  // https://github.com/foundationkit/FoundationKit/blob/master/Sources/NSNotificationCenter+FKMainThread.m
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([delegate respondsToSelector:@selector(notifierWillPostNotices)]) {
      [delegate notifierWillPostNotices];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:EBNotifierWillPostNoticesNotification object:self];
  });

  // create url
  NSString *URLString = [NSString stringWithFormat:@"%@://%@/notifier_api/v2/notices",
                                                   (__useSSL ? @"https" : @"http"),
                                                   __hostName];
  NSURL *URL = [NSURL URLWithString:URLString];

#if TARGET_OS_IPHONE
  // start background task
  __block BOOL keepPosting = YES;
  UIApplication *app = [UIApplication sharedApplication];
  UIBackgroundTaskIdentifier task = [app beginBackgroundTaskWithExpirationHandler:^{
    keepPosting = NO;
  }];
    
  // report each notice
  [paths enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    if (keepPosting) {
      [self postNoticeWithContentsOfFile:obj toURL:URL];
    } else {
      *stop = YES;
    }
  }];
    
  // end background task
  if (task != UIBackgroundTaskInvalid) {
    [app endBackgroundTask:task];
  }
#else
    // report each notice
    [paths enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        [self postNoticeWithContentsOfFile:obj toURL:URL];
    }];      
#endif

  // notify people
  dispatch_async(dispatch_get_main_queue(), ^{
    if ([delegate respondsToSelector:@selector(notifierDidPostNotices)]) {
      [delegate notifierDidPostNotices];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:EBNotifierDidPostNoticesNotification object:self];
  });
	
}

+ (void)postNoticeWithContentsOfFile:(NSString *)path toURL:(NSURL *)URL {
    
  // assert
  NSAssert(![NSThread isMainThread], @"This method must not be called on the main thread");
    
  // create url request
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
	[request setTimeoutInterval:10.0];
	[request setValue:@"text/xml" forHTTPHeaderField:@"Content-Type"];
	[request setHTTPMethod:@"POST"];
    
	// get notice payload
  EBNotice *notice = [EBNotice noticeWithContentsOfFile:path];

#ifdef DEBUG
    EBLog(@"%@", notice);
#endif

  NSString *XMLString = [notice errbitXMLString];
  if (XMLString) {
    NSData *data = [XMLString dataUsingEncoding:NSUTF8StringEncoding];
    [request setHTTPBody:data];
  } else {
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    return;
  }
	
	// perform request
  NSError *error = nil;
	NSHTTPURLResponse *response = nil;
    
#ifdef DEBUG
  NSData *responseBody =
#endif

  [NSURLConnection sendSynchronousRequest:request
                        returningResponse:&response
                                    error:&error];

  NSInteger statusCode = [response statusCode];
	
	// error checking
  if (error) {
    EBLog(@"Encountered error while posting notice.");
    EBLog(@"%@", error);
    return;
  } else {
    [[NSFileManager defaultManager] removeItemAtPath:path
                                               error:nil];
  }
	
	// great success
	if (statusCode == 200) {
    EBLog(@"Crash report posted");
	} else if (statusCode == 403) {
    // forbidden
    EBLog(@"Please make sure that your API key is correct and that your project supports SSL.");
  } else if (statusCode == 422) {
      // invalid post
    EBLog(@"The posted notice payload is invalid.");

#ifdef DEBUG
    EBLog(@"%@", XMLString);
#endif
  } else {
    // unknown
    EBLog(@"Encountered unexpected status code: %ld", (long)statusCode);

#ifdef DEBUG
    NSString *responseString = [[NSString alloc] initWithData:responseBody
                                                     encoding:NSUTF8StringEncoding];
    EBLog(@"%@", responseString);
#endif
  }
}

#pragma mark - cache methods
+ (void)cacheUserDataDictionary {
  @synchronized(self) {

    // free old cached value
    free(eb_signal_info.user_data);
    eb_signal_info.user_data_length = 0;
    eb_signal_info.user_data = nil;

    // cache new value
    if (__userData) {
      NSData *data = [NSKeyedArchiver archivedDataWithRootObject:__userData];
      unsigned long length = [data length];
      eb_signal_info.user_data = malloc(length);
      [data getBytes:eb_signal_info.user_data length:length];
      eb_signal_info.user_data_length = length;
    }
  }
}

#pragma mark - user interface
+ (void)showNoticeAlertForNoticesWithPaths:(NSArray *)paths {
  // assert
  NSAssert([NSThread isMainThread], @"This method must be called on the main thread");
  NSAssert([paths count], @"No paths were provided");
    
  // get delegate
  id<EBNotifierDelegate> delegate = [self delegate];
    
  // alert title
  NSString *title = nil;
  if ([delegate respondsToSelector:@selector(titleForNoticeAlert)]) {
    title = [delegate titleForNoticeAlert];
  }

  if (title == nil) {
    title = EBLocalizedString(@"NOTICE_TITLE");
  }
    
  // alert body
  NSString *body = nil;
  if ([delegate respondsToSelector:@selector(bodyForNoticeAlert)]) {
    body = [delegate bodyForNoticeAlert];
  }

  if (body == nil) {
    body = [NSString stringWithFormat:EBLocalizedString(@"NOTICE_BODY"), EBNotifierApplicationName()];
  }
    
  // declare blocks
  void (^delegateDismissBlock) (void) = ^{
    if ([delegate respondsToSelector:@selector(notifierDidDismissAlert)]) {
      [delegate notifierDidDismissAlert];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:EBNotifierDidDismissAlertNotification
                                                        object:self];
  };

  void (^delegatePresentBlock) (void) = ^{
    if ([delegate respondsToSelector:@selector(notifierWillDisplayAlert)]) {
      [delegate notifierWillDisplayAlert];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:EBNotifierWillDisplayAlertNotification
                                                        object:self];
  };

  void (^postNoticesBlock) (void) = ^{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      [self postNoticesWithPaths:paths];
    });
  };

  void (^deleteNoticesBlock) (void) = ^{
    NSFileManager *manager = [NSFileManager defaultManager];
    [paths enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
      [manager removeItemAtPath:obj error:nil];
    }];
  };

  void (^setDefaultsBlock) (void) = ^{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:EBNotifierAlwaysSendKey];
    [defaults synchronize];
  };

#if TARGET_OS_IPHONE
  GCAlertView *alert = [[GCAlertView alloc] initWithTitle:title message:body];
  [alert addButtonWithTitle:EBLocalizedString(@"ALWAYS_SEND") block:^{
    setDefaultsBlock();
    postNoticesBlock();
  }];

  [alert addButtonWithTitle:EBLocalizedString(@"SEND") block:postNoticesBlock];
  [alert addButtonWithTitle:EBLocalizedString(@"DONT_SEND") block:deleteNoticesBlock];
  [alert setDidDismissBlock:delegateDismissBlock];
  [alert setDidDismissBlock:delegatePresentBlock];
  [alert setCancelButtonIndex:2];
  [alert show];
#endif
}

#pragma mark - reachability
+ (BOOL)isReachable:(SCNetworkReachabilityFlags)flags {
  if ((flags & kSCNetworkReachabilityFlagsReachable) == 0) {
    return NO;
  }

  if ((flags & kSCNetworkReachabilityFlagsConnectionRequired) == 0) {
    return YES;
  }

  if  (((flags & kSCNetworkReachabilityFlagsConnectionOnDemand) != 0) ||
      ((flags & kSCNetworkReachabilityFlagsConnectionOnTraffic) != 0)) {
        if ((flags & kSCNetworkReachabilityFlagsInterventionRequired) == 0) {
          return YES;
        }
  }
  return NO;
}

@end

#pragma mark - reachability change
void EBNotifierReachabilityDidChange(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
  if ([EBNotifier isReachable:flags]) {
    static dispatch_once_t token;
    dispatch_once(&token, ^{
      NSArray *paths = [EBNotifier pathsForAllNotices];
      if ([paths count]) {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:EBNotifierAlwaysSendKey] ||
              !__displayPrompt) {
          dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [EBNotifier postNoticesWithPaths:paths];
          });
        } else {
          [EBNotifier showNoticeAlertForNoticesWithPaths:paths];
        }
      }
    });
  }
}
