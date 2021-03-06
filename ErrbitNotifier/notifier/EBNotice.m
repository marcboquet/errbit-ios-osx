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

#import <objc/runtime.h>

#import "EBNotice.h"
#import "EBNotifierFunctions.h"

#import "EBNotifier.h"

#import "DDXML.h"

// library constants
NSString * const EBNotifierOperatingSystemVersionKey    = @"Operating System";
NSString * const EBNotifierApplicationVersionKey        = @"Application Version";
NSString * const EBNotifierPlatformNameKey              = @"Platform";
NSString * const EBNotifierEnvironmentNameKey           = @"Environment Name";
NSString * const EBNotifierBundleVersionKey             = @"Bundle Version";
NSString * const EBNotifierExceptionNameKey             = @"Exception Name";
NSString * const EBNotifierExceptionReasonKey           = @"Exception Reason";
NSString * const EBNotifierCallStackKey                 = @"Call Stack";
NSString * const EBNotifierControllerKey                = @"Controller";
NSString * const EBNotifierExecutableKey                = @"Executable";
NSString * const EBNotifierExceptionParametersKey       = @"Exception Parameters";
NSString * const EBNotifierNoticePathExtension          = @"htnotice";

const int EBNotifierNoticeVersion         = 5;
const int EBNotifierSignalNoticeType      = 1;
const int EBNotifierExceptionNoticeType   = 2;

@interface EBNotice ()
@property (nonatomic, copy) NSString        *environmentName;
@property (nonatomic, copy) NSString        *bundleVersion;
@property (nonatomic, copy) NSString        *exceptionName;
@property (nonatomic, copy) NSString        *exceptionReason;
@property (nonatomic, copy) NSString        *controller;
@property (nonatomic, copy) NSString        *action;
@property (nonatomic, copy) NSString        *executable;
@property (nonatomic, copy) NSArray         *callStack;
@property (nonatomic, strong) NSNumber      *noticeVersion;
@property (nonatomic, copy) NSDictionary    *environmentInfo;
@end

@implementation EBNotice

@synthesize noticeVersion   = __noticeVersion;
@synthesize environmentName = __environmentName;
@synthesize bundleVersion   = __bundleVersion;
@synthesize exceptionName   = __exceptionName;
@synthesize exceptionReason = __exceptionReason;
@synthesize controller      = __controller;
@synthesize callStack       = __callStack;
@synthesize environmentInfo = __environmentInfo;
@synthesize action          = __action;
@synthesize executable      = __executable;

- (id)initWithContentsOfFile:(NSString *)path {
  self = [super init];

  if (self) {
    @try {
      // check path
      NSString * extension = [path pathExtension];
      if (![extension isEqualToString:EBNotifierNoticePathExtension]) {
        [NSException raise:NSInvalidArgumentException
                    format:@"%@ is not a valid notice", path];
      }

      // setup
      NSData * data = [NSData dataWithContentsOfFile:path];
      NSData * subdata = nil;
      NSDictionary * dictionary = nil;
      unsigned long location = 0;
      unsigned long length = 0;

      // get version
      int version;
      [data getBytes:&version
               range:NSMakeRange(location, sizeof(int))];

      location += sizeof(int);
      if (version < 5) {
        [NSException raise:NSInternalInconsistencyException
                    format:@"The notice at %@ is not compatible with this version of the notifier", path];
      }
      self.noticeVersion = [NSNumber numberWithInt:version];

      // get type
      int type;
      [data getBytes:&type
               range:NSMakeRange(location, sizeof(int))];

      location += sizeof(int);

      // get notice payload
      [data getBytes:&length
               range:NSMakeRange(location, sizeof(unsigned long))];

      location += sizeof(unsigned long);
      subdata = [data subdataWithRange:NSMakeRange(location, length)];
      location += length;
      dictionary = [NSKeyedUnarchiver unarchiveObjectWithData:subdata];
      self.environmentName  = [dictionary objectForKey:EBNotifierEnvironmentNameKey];
      self.bundleVersion    = [dictionary objectForKey:EBNotifierBundleVersionKey];
      self.executable       = [dictionary objectForKey:EBNotifierExecutableKey];

      // get user data
      [data getBytes:&length
               range:NSMakeRange(location, sizeof(unsigned long))];

      location += sizeof(unsigned long);
      subdata = [data subdataWithRange:NSMakeRange(location, length)];
      location += length;
      self.environmentInfo = [NSKeyedUnarchiver unarchiveObjectWithData:subdata];

      // signal notice
      if (type == EBNotifierSignalNoticeType) {
        // signal
        int signal;
        [data getBytes:&signal
                 range:NSMakeRange(location, sizeof(int))];

        location += sizeof(int);

        // exception name
        self.exceptionName = [NSString stringWithUTF8String:strsignal(signal)];
        self.exceptionReason = @"Application recieved signal";

        // call stack
        length = [data length] - location;
        char * string = malloc(length + 1);
        const char * bytes = [data bytes];

        for (unsigned long i = 0; location < [data length]; location++) {
          if (bytes[location] != '\0') {
            string[i++] = bytes[location];
          }
        }

        NSArray * lines = [[NSString stringWithUTF8String:string] componentsSeparatedByString:@"\n"];
        NSPredicate * lengthPredicate = [NSPredicate predicateWithBlock:^BOOL(id object, NSDictionary *bindings) {
          return ([object length] > 0);
        }];

        self.callStack = [lines filteredArrayUsingPredicate:lengthPredicate];
        free(string);

      }

      // exception notice
      else if (type == EBNotifierExceptionNoticeType) {

        // exception payload
        [data getBytes:&length
                 range:NSMakeRange(location, sizeof(unsigned long))];

        location += sizeof(unsigned long);
        subdata = [data subdataWithRange:NSMakeRange(location, length)];
        dictionary = [NSKeyedUnarchiver unarchiveObjectWithData:subdata];
        self.exceptionName = [dictionary objectForKey:EBNotifierExceptionNameKey];
        self.exceptionReason = [dictionary objectForKey:EBNotifierExceptionReasonKey];
        self.callStack = [dictionary objectForKey:EBNotifierCallStackKey];
        self.controller = [dictionary objectForKey:EBNotifierControllerKey];
        NSMutableDictionary *mutableInfo = [self.environmentInfo mutableCopy];
        [mutableInfo addEntriesFromDictionary:[dictionary objectForKey:EBNotifierExceptionParametersKey]];
        self.environmentInfo = mutableInfo;

      }

      // finish up call stack stuff
      self.callStack = EBNotifierParseCallStack(self.callStack);
      self.action = EBNotifierActionFromParsedCallStack(self.callStack, self.executable);
      if (type == EBNotifierSignalNoticeType && self.action != nil) {
        self.exceptionReason = self.action;
      }

    }
    @catch (NSException *exception) {
      EBLog(@"%@", exception);
      return nil;
    }
  }
  return self;
}

+ (EBNotice *)noticeWithContentsOfFile:(NSString *)path {
  return [[EBNotice alloc] initWithContentsOfFile:path];
}

- (NSString *)errbitXMLString {
    
  // create root
  DDXMLElement *notice = [DDXMLElement elementWithName:@"notice"];
  [notice addAttribute:[DDXMLElement attributeWithName:@"version"
                                           stringValue:@"2.1"]];
    
  // set api key
  NSString *APIKey = [EBNotifier APIKey];
  if (APIKey == nil) { APIKey = @""; }
  [notice addChild:[DDXMLElement elementWithName:@"api-key"
                                     stringValue:APIKey]];
    
  // set notifier information
  DDXMLElement *notifier = [DDXMLElement elementWithName:@"notifier"];
  [notifier addChild:[DDXMLElement elementWithName:@"name"
                                       stringValue:@"Errbit iOS Notifier"]];

  [notifier addChild:[DDXMLElement elementWithName:@"url"
                                       stringValue:@"http://github.com/guicocoa/errbit-ios"]];

	[notifier addChild:[DDXMLElement elementWithName:@"version"
                                       stringValue:EBNotifierVersion]];

	[notice addChild:notifier];
    
	// set error information
  NSString *message = [NSString stringWithFormat:@"%@: %@", self.exceptionName, self.exceptionReason];
  DDXMLElement *error = [DDXMLElement elementWithName:@"error"];
  [error addChild:[DDXMLElement elementWithName:@"class"
                                    stringValue:self.exceptionName]];

	[error addChild:[DDXMLElement elementWithName:@"message"
                                    stringValue:message]];

  DDXMLElement *backtrace = [DDXMLElement elementWithName:@"backtrace"];
  [self.callStack enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    DDXMLElement *line = [DDXMLElement elementWithName:@"line"];
    [line addAttribute:[DDXMLElement attributeWithName:@"number"
                                           stringValue:[(NSArray *)obj objectAtIndex:1]]];

    [line addAttribute:[DDXMLElement attributeWithName:@"file"
                                           stringValue:[(NSArray *)obj objectAtIndex:2]]];

    [line addAttribute:[DDXMLElement attributeWithName:@"method"
                                           stringValue:[(NSArray *)obj objectAtIndex:3]]];

    [backtrace addChild:line];
  }];

  [error addChild:backtrace];
  [notice addChild:error];
    
  // set request info
  DDXMLElement *request = [DDXMLElement elementWithName:@"request"];
  [request addChild:[DDXMLElement elementWithName:@"url"]];
  [request addChild:[DDXMLElement elementWithName:@"component"
                                      stringValue:self.controller]];

  [request addChild:[DDXMLElement elementWithName:@"action"
                                      stringValue:self.action]];

  DDXMLElement *cgi = [DDXMLElement elementWithName:@"cgi-data"];
  [self.environmentInfo enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
    DDXMLElement *entry = [DDXMLElement elementWithName:@"var"
                                            stringValue:[obj description]];

    [entry addAttribute:[DDXMLElement attributeWithName:@"key"
                                            stringValue:[key description]]];

    [cgi addChild:entry];
  }];

  [request addChild:cgi];
  [notice addChild:request];
    
  // set server encironment
  DDXMLElement *environment = [DDXMLElement elementWithName:@"server-environment"];
  [environment addChild:[DDXMLElement elementWithName:@"environment-name"
                                          stringValue:self.environmentName]];

  [environment addChild:[DDXMLElement elementWithName:@"app-version"
                                          stringValue:self.bundleVersion]];

	[notice addChild:environment];
    
  // get return value
  NSString *XMLString = [[notice XMLString] copy];
    
  // return
  return XMLString;
}

- (NSString *)description {
	unsigned int count;
	objc_property_t *properties = class_copyPropertyList([self class], &count);
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:count];

	for (unsigned int i = 0; i < count; i++) {
		NSString *name = [NSString stringWithUTF8String:property_getName(properties[i])];
		NSString *value = [self valueForKey:name];
      if (value) {
        [dictionary setObject:value forKey:name];
      } else {
        [dictionary setObject:[NSNull null] forKey:name];
      }
	}

	free(properties);
  return [NSString stringWithFormat:@"%@ %@", [super description], [dictionary description]];
}

@end
