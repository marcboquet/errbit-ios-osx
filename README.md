# About

The Errbit iOS Notifier is designed to give developers instant notification of problems that occur in their apps. With just a few lines of code, your app will automatically phone home whenever a crash or exception is encountered. These reports go straight to your own copy of [Errbit](https://github.com/errbit/errbit) where you can see information like backtrace, device type, app version, and more.

To see how this might help you, check out [this screencast](http://guicocoa.com/airbrake). If you have questions or need support, please visit [Errbit iOS support](https://github.com/rjhancock/errbit-ios/issues)

The notifier requires iOS 6.0 or higher for iOS projects.

This project was originally forked from [Airbrake iOS Notifier](https://github.com/airbrake/airbrake-ios)

# Signals

The notifier handles all unhandled exceptions, and a select list of Unix signals:

- `SIGABRT`
- `SIGBUS`
- `SIGFPE`
- `SIGILL`
- `SIGSEGV`
- `SIGTRAP`

# Symbolication

In order for the call stack to be properly symbolicated at the time of a crash, applications built with the notifier should not be stripped of their symbol information at compile time. If these settings are not set as recommended, frames from your binary will be displayed as hex return addresses instead of readable strings. These hex return addresses can be symbolicated using `atos`. More information about symbolication and these build settings can be found in Apple's [developer documentation](http://developer.apple.com/tools/xcode/symbolizingcrashdumps.html). Here are the settings that control code stripping:

- Deployment Postprocessing: Off
- Strip Debug Symbols During Copy: Off
- Strip Linked Product: Off

# Installation

These instructions written using Xcode 4.4+.

1. Drag the project file into your project.
2. Under Project -> Build Phases -> Target Dependencies, add "ErrbitNotifier"
3. Under Project -> Build Phases -> Link Binary With Libraries, add "libErrbitNotifier.a", "libxml2.dylib", and "SystemConfiguration.framework"
4. Under Project -> Build Settings -> Header Search Paths, add "$(BUILT_PRODUCTS_DIR)/../../Headers" (with quotes)
5. Under Project -> Build Settings -> Other Linker Flags, add -ObjC and -all_load
6. Add the following to your Localizable.strings file as well as any localized versions you want

````objc
"NOTICE_TITLE" = "Crash Report";
"NOTICE_BODY" = "%@ has detected unreported crashes, would you like to send a report to the developer?";
"SEND" = "Send";
"DONT_SEND" = "Don't Send";
"ALWAYS_SEND" = "Always Send";
````

# Running The Notifier

The `EBNotifier` class is the primary class you will interact with while using the notifier. All of its methods and properties, along with the `EBNotifierDelegate` protocol are documented in their headers. **Please read through the header files for a complete reference of the library.**

To run the notifier you only need to complete two steps. First, import the `EBNotifier` header file in your app delegate

````objc
#import <ErrbitNotifier/EBNotifier.h>
````

Next, call the start notifier method at the very beginning of your `application:didFinishLaunchingWithOptions:`

````objective-c
[EBNotifier startNotifierWithAPIKey:@"key"
                      serverAddress:@"errbit.server.com"
                    environmentName:EBNotifierAutomaticEnvironment
                             useSSL:YES // only if your account supports it
                           delegate:self];
````

The API key argument expects your Airbrake project API key. The environment name you provide will be used to categorize received crash reports in the Airbrake web interface. The notifier provides several factory environment names that you are free to use.

- EBNotifierAutomaticEnvironment
- EBNotifierDevelopmentEnvironment
- EBNotifierAdHocEnvironment
- EBNotifierAppStoreEnvironment
- EBNotifierReleaseEnvironment

The `EBNotifierAutomaticEnvironment` environment will set the environment to release or development depending on the presence of the `DEBUG` macro.

# Exception Logging

As of version 3.0 of the notifier, you can log your own exceptions at any time.

````objective-c
@try {
    // something dangerous
}
@catch (NSException *e) {
    [EBNotifier logException:e];
}
````

# Debugging

To test that the notifier is working inside your application, a simple test method is provided. This method raises an exception, catches it, and reports it as if a real crash happened. Add this code to your `application:didFinishLaunchingWithOptions:` to test the notifier:

````objective-c
[EBNotifier writeTestNotice];
````

If you use the `DEBUG` macro to signify development builds the notifier will log notices and errors to the console as they are reported to help see more details.

#Implementing the Delegate Protocol

The `EBNotifierDelegate` protocol allows you to respond to actions going on inside the notifier as well as provide runtime customizations. As of version 3.0 of the notifier, a matching set of notifications are posted to `NSNotificationCenter`. All of the delegate methods in the `EBNotifierDelegate` protocol are documented in `EBNotifierDelegate.h`. Here are just a few of those methods:

**MyAppDelegate.h**

````objective-c
#import <ErrbitNotifier/EBNotifier.h>

@interface MyAppDelegate : NSObject <UIApplicationDelegate, EBNotifierDelegate>

// your properties and methods

@end
````

**MyAppDelegate.m**

````objective-c
@implementation MyAppDelegate

// your other methods

#pragma mark - notifier delegate
/*
  These are only a few of the delegate methods you can implement.
  The rest are documented in ABNotifierDelegate.h. All of the
  delegate methods are optional.
*/
- (void)notifierWillDisplayAlert {
  [gameController pause];
}
- (void)notifierDidDismissAlert {
  [gameController resume];
}
- (NSString *)titleForNoticeAlert {
  return @"Oh Noes!";
}
- (NSString *)bodyForNoticeAlert {
  return @"MyApp has detected unreported crashes, would you like to send a report to the developer?";
}

@end
````

# Contributors

- [Caleb Davenport](http://guicocoa.com)
- [Marshall Huss](http://twoguys.us)
- [Matt Coneybeare](http://coneybeare.net)
- [Benjamin Broll](http://twitter.com/bebroll)
- Sergei Winitzki
- Irina Anastasiu
- [Jordan Breeding](http://jordanbreeding.com)
- [LithiumCorp](http://lithiumcorp.com)
- [Mathijs Kadijk](http://www.wrep.nl/)
