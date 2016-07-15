//
//  Middleware.m
//  Copyright © 2016 VoIPGRID. All rights reserved.
//

#import "Middleware.h"

#import "APNSHandler.h"
#import "Configuration.h"
#import "MiddlewareRequestOperationManager.h"
#import "ReachabilityManager.h"
#import "SIPUtils.h"
#import "SSKeychain.h"
#import "SystemUser.h"
#import "Vialer-Swift.h"

static NSString * const MiddlewareAPNSPayloadKeyType       = @"type";
static NSString * const MiddlewareAPNSPayloadKeyCall       = @"call";
static NSString * const MiddlewareAPNSPayloadKeyCheckin    = @"checkin";
static NSString * const MiddlewareAPNSPayloadKeyMessage    = @"message";

static NSString * const MiddlewareAPNSPayloadKeyResponseAPI = @"response_api";

NSString * const MiddlewareRegistrationOnOtherDeviceNotification = @"MiddlewareRegistrationOnOtherDeviceNotification";

@interface Middleware ()
@property (strong, nonatomic) MiddlewareRequestOperationManager *commonMiddlewareRequestOperationManager;
@property (weak, nonatomic) SystemUser *systemUser;
@property (strong, nonatomic) ReachabilityManager *reachabilityManager;
@property (nonatomic) int retryCount;
@end

@implementation Middleware

#pragma mark - Lifecycle
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SystemUserSIPCredentialsChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:SystemUserSIPDisabledNotification object:nil];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateAPNSTokenOnSIPCredentialsChange) name:SystemUserSIPCredentialsChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deleteDeviceRegistrationFromMiddleware:) name:SystemUserSIPDisabledNotification object:nil];
    }
    return self;
}

#pragma mark - properties
- (SystemUser *)systemUser {
    if (!_systemUser) {
        _systemUser = [SystemUser currentUser];
    }
    return _systemUser;
}

/**
 *  There is one Common Middleware used for registering and unregistration of a device.
 *  Responding to an incoming call is done to the middleware which is included in the push payload.
 *
 *  @return A Middleware instance representing the common middleware.
 */
- (MiddlewareRequestOperationManager *)commonMiddlewareRequestOperationManager {
    if (!_commonMiddlewareRequestOperationManager) {
        NSString *baseURLString = [[Configuration defaultConfiguration] UrlForKey:ConfigurationMiddleWareBaseURLString];
        _commonMiddlewareRequestOperationManager = [[MiddlewareRequestOperationManager alloc] initWithBaseURLasString:baseURLString];
    }
    return _commonMiddlewareRequestOperationManager;
}

- (ReachabilityManager *)reachabilityManager {
    if (!_reachabilityManager) {
        _reachabilityManager = [[ReachabilityManager alloc] init];
    }
    return _reachabilityManager;
}

#pragma mark - actions
- (void)handleReceivedAPSNPayload:(NSDictionary *)payload {
    // Set current time to measure response time.
    NSDate *pushResponseTimeMeasurementStart = [NSDate date];

    NSString *payloadType = payload[MiddlewareAPNSPayloadKeyType];
    DDLogDebug(@"Push message received from middleware of type: %@", payloadType);
    DDLogVerbose(@"Payload:\n%@", payload);

    if ([payloadType isEqualToString:MiddlewareAPNSPayloadKeyCall]) {
        // Incoming call.

        if ([self.reachabilityManager resetAndGetCurrentReachabilityStatus] == ReachabilityManagerStatusHighSpeed && [SystemUser currentUser].sipEnabled) {
            // User has good enough connection and is SIP Enabled.
            // Register the account with the endpoint.
            [SIPUtils registerSIPAccountWithEndpointWithCompletion:^(BOOL success, VSLAccount *account) {
                if (success) {
                    DDLogDebug(@"SIP Endpoint registration success! Sending Available = YES to middleware");
                } else {
                    DDLogDebug(@"SIP Endpoint registration FAILED. Senting Available = NO to middleware");
                }
                [self respondToMiddleware:payload isAvailable:success withAccount:account andPushResponseTimeMeasurementStart:pushResponseTimeMeasurementStart];
            }];
        } else {
            // User is not SIP enabled or the connection is not good enough.
            // Sent not available to the middleware.
            DDLogDebug(@"Not accepting call, connection quality insufficient or SIP Disabled, Sending Available = NO to middleware");
            [self respondToMiddleware:payload isAvailable:NO withAccount:nil andPushResponseTimeMeasurementStart:pushResponseTimeMeasurementStart];
        }
    } else if ([payloadType isEqualToString:MiddlewareAPNSPayloadKeyCheckin]) {

    } else if ([payloadType isEqualToString:MiddlewareAPNSPayloadKeyMessage]) {
        if (self.systemUser.sipEnabled) {
            self.systemUser.sipEnabled = NO;
            NSNotification *notification = [NSNotification notificationWithName:MiddlewareRegistrationOnOtherDeviceNotification object:nil];
            [[NSNotificationQueue defaultQueue] enqueueNotification:notification postingStyle:NSPostASAP];
        }
    }
}

- (void)respondToMiddleware:(NSDictionary *)payload isAvailable:(BOOL)available withAccount:(VSLAccount *)account andPushResponseTimeMeasurementStart:(NSDate *)pushResponseTimeMeasurmentStart  {
    // Track the response that is sent to the middleware.
    NSString *connectionTypeString = [self.reachabilityManager currentConnectionTypeString];
    [VialerGAITracker pushNotificationWithIsAccepted:available connectionType:connectionTypeString];

    NSString *middlewareBaseURLString = payload[MiddlewareAPNSPayloadKeyResponseAPI];
    DDLogDebug(@"Responding to Middleware with URL: %@", middlewareBaseURLString);
    MiddlewareRequestOperationManager *middlewareToRespondTo = [[MiddlewareRequestOperationManager alloc] initWithBaseURLasString:middlewareBaseURLString];

    [middlewareToRespondTo sentCallResponseToMiddleware:payload isAvailable:available withCompletion:^(NSError * _Nullable error) {
        // Whole response cycle completed, log duration.
        NSTimeInterval responseTime = [[NSDate date] timeIntervalSinceDate:pushResponseTimeMeasurmentStart];
        [VialerGAITracker respondedToIncomingPushNotificationWithResponseTime:responseTime];
        DDLogDebug(@"Middleware response time: [%f s]", responseTime);

        if (error) {
            // Not only do we want to unregister upon a 408 but on every error.
            [account unregisterAccount:nil];
            DDLogError(@"The middleware responded with an error: %@", error);
        } else {
            DDLogDebug(@"Succsesfully sent \"availabe: %@\" to middleware", available ? @"YES" : @"NO");
        }
    }];
}

/**
 *  Invoked when the SystemUserSIPCredentialsChangedNotification is received.
 */
- (void)updateAPNSTokenOnSIPCredentialsChange {
    if (self.systemUser.sipEnabled) {
        DDLogInfo(@"Sip Credentials have changed, updating Middleware");
        [self sentAPNSToken:[APNSHandler storedAPNSToken]];
    }
}

- (void)deleteDeviceRegistrationFromMiddleware:(NSNotification *)notification {
    DDLogInfo(@"SIP Disabled, unregistering from middleware");
    NSString *storedAPNSToken = [APNSHandler storedAPNSToken];
    NSString *sipAccount = notification.object;

    if (sipAccount && storedAPNSToken) {
        [self.commonMiddlewareRequestOperationManager deleteDeviceRecordWithAPNSToken:storedAPNSToken sipAccount:sipAccount withCompletion:^(NSError *error) {
            if (error) {
                DDLogError(@"Error deleting device record from middleware. %@", error);
            } else {
                DDLogDebug(@"Middleware device record deleted successfully");
            }
        }];
    } else {
        DDLogDebug(@"Not deleting device registration from middleware, SIP Account(%@) not set or no APNS Token(%@) stored.",
                   sipAccount, storedAPNSToken);
    }
}

- (void)sentAPNSToken:(NSString *)apnsToken {
    // This is for debuging, can be removed in the future
    // Inserted to debug VIALI-3176. Remove with VIALI-3178
    NSString *applicationState;
    switch ([UIApplication sharedApplication].applicationState) {
            case UIApplicationStateActive: {
                applicationState = @"UIApplicationStateActive";
                break;
            }
            case UIApplicationStateInactive: {
                applicationState = @"UIApplicationStateInactive";
                break;
            }
            case UIApplicationStateBackground: {
                applicationState = @"UIApplicationStateBackground";
                break;
            }
    }

    NSString *backgroundTimeRemaining = @"N/A";
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        backgroundTimeRemaining = [NSString stringWithFormat:@"%.4f", [UIApplication sharedApplication].backgroundTimeRemaining];
    }

    DDLogInfo(@"Trying to sent APNSToken to middleware. Application state: \"%@\". Background time remaining: %@", applicationState, backgroundTimeRemaining);
    // End debugging statements

    UIApplication *application = [UIApplication sharedApplication];
    UIBackgroundTaskIdentifier __block backgroundtask = UIBackgroundTaskInvalid;

    void (^backgroundTaskCleanupBlock)(void) = ^{
        [application endBackgroundTask:backgroundtask];
        backgroundtask = UIBackgroundTaskInvalid;
    };

    backgroundtask = [application beginBackgroundTaskWithExpirationHandler:^{
        DDLogInfo(@"APNS token background task timed out.");
        backgroundTaskCleanupBlock();
    }];

    [self sentAPNSToken:apnsToken withCompletion:^(NSError *error) {
        NSMutableString *logString = [NSMutableString stringWithFormat:@"APNS token background task completed"];
        if (application.applicationState == UIApplicationStateBackground) {
            [logString appendFormat:@" with %.3f time remaining", application.backgroundTimeRemaining];
        }

        DDLogInfo(@"%@", logString);
        backgroundTaskCleanupBlock();
    }];
}

- (void)sentAPNSToken:(NSString *)apnsToken withCompletion:(void (^)(NSError *error))completion {
    if (self.systemUser.sipEnabled) {
        [self.commonMiddlewareRequestOperationManager updateDeviceRecordWithAPNSToken:apnsToken sipAccount:self.systemUser.sipAccount withCompletion:^(NSError *error) {
            if (error) {

                if ((error.code == NSURLErrorTimedOut || error.code == NSURLErrorNotConnectedToInternet) && self.retryCount < 5) {
                    // Update the retry count.
                    self.retryCount++;

                    // Log an error.
                    DDLogWarn(@"Device registration failed. Will retry 5 times. Currently tried %d out of 5.", self.retryCount);

                    // Retry to call the function.
                    [self sentAPNSToken:apnsToken withCompletion:completion];
                } else {
                    // Sending token failed because device isn't online. Register failed registration, but keep
                    // SIP calling enabled.

                    // Reset the retry count back to 0.
                    self.retryCount = 0;

                    // Log the problem to track failures.
                    [VialerGAITracker registrationFailedWithMiddleWareException];
                    DDLogError(@"Device registration with Middleware failed. %@", error);

                    if (completion) {
                        completion(error);
                    }
                }
            } else {
                // Reset the retry count back to 0.
                self.retryCount = 0;

                // Display debug message the registration has been successfull.
                DDLogDebug(@"Middleware registration successfull.");
                if (completion) {
                    completion(nil);
                }
            }
        }];
    }
}

@end
