/*! @file OIDAuthorizationUICoordinatorIOS.m
    @brief AppAuth iOS SDK
    @copyright
        Copyright 2016 Google Inc. All Rights Reserved.
    @copydetails
        Licensed under the Apache License, Version 2.0 (the "License");
        you may not use this file except in compliance with the License.
        You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

        Unless required by applicable law or agreed to in writing, software
        distributed under the License is distributed on an "AS IS" BASIS,
        WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
        See the License for the specific language governing permissions and
        limitations under the License.
 */

#import "OIDAuthorizationUICoordinatorIOS.h"

#import <SafariServices/SafariServices.h>

#import "OIDAuthorizationRequest.h"
#import "OIDAuthorizationService.h"
#import "OIDErrorUtilities.h"

NS_ASSUME_NONNULL_BEGIN

/** @brief The global/shared Safari view controller factory. Responsible for creating all new
        instances of @c SFSafariViewController.
 */
static id<OIDSafariViewControllerFactory> __nullable gSafariViewControllerFactory;

/** @brief The default @c OIDSafariViewControllerFactory which creates new instances of
        @c SFSafariViewController using known best practices.
 */
@interface OIDDefaultSafariViewControllerFactory : NSObject<OIDSafariViewControllerFactory>
@end

@interface OIDAuthorizationUICoordinatorIOS ()<SFSafariViewControllerDelegate>
@end

@implementation OIDAuthorizationUICoordinatorIOS {
  UIViewController *_presentingViewController;

  BOOL _authorizationFlowInProgress;
  __weak id<OIDAuthorizationFlowSession> _session;
  __weak SFSafariViewController *_safariVC;
  id _authenticationVC;
}

/** @brief Obtains the current @c OIDSafariViewControllerFactory; creating a new default instance if
        required.
 */
+ (id<OIDSafariViewControllerFactory>)safariViewControllerFactory {
  if (!gSafariViewControllerFactory) {
    gSafariViewControllerFactory = [[OIDDefaultSafariViewControllerFactory alloc] init];
  }
  return gSafariViewControllerFactory;
}

+ (void)setSafariViewControllerFactory:(id<OIDSafariViewControllerFactory>)factory {
  NSAssert(factory, @"Parameter: |factory| must be non-nil.");
  gSafariViewControllerFactory = factory;
}

- (nullable instancetype)initWithPresentingViewController:
        (UIViewController *)presentingViewController {
  self = [super init];
  if (self) {
    _presentingViewController = presentingViewController;
  }
  return self;
}

- (BOOL)presentAuthorizationRequest:(OIDAuthorizationRequest *)request
                            session:(id<OIDAuthorizationFlowSession>)session {
  if (_authorizationFlowInProgress) {
    // TODO: Handle errors as authorization is already in progress.
    return NO;
  }

  _authorizationFlowInProgress = YES;
  _session = session;
  BOOL openedSafari = NO;
  NSURL *requestURL = [request authorizationRequestURL];

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
  if (@available(iOS 11.0, *)) {
    NSString *redirectScheme = request.redirectURL.scheme;
    SFAuthenticationSession* authenticationVC =
        [[SFAuthenticationSession alloc] initWithURL:requestURL
                                   callbackURLScheme:redirectScheme
                                   completionHandler:^(NSURL * _Nullable callbackURL,
                                                       NSError * _Nullable error) {
      _authenticationVC = nil;
      if (callbackURL) {
        [_session resumeAuthorizationFlowWithURL:callbackURL];
      } else {
        NSError *safariError =
            [OIDErrorUtilities errorWithCode:OIDErrorCodeUserCanceledAuthorizationFlow
                             underlyingError:error
                                 description:nil];
        [_session failAuthorizationFlowWithError:safariError];
      }
    }];
    _authenticationVC = authenticationVC;
    openedSafari = [authenticationVC start];
  } else
#endif // __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
  {
    if ([SFSafariViewController class]) {
      SFSafariViewController *safariVC =
      [[[self class] safariViewControllerFactory] safariViewControllerWithURL:requestURL];
      safariVC.delegate = self;
      _safariVC = safariVC;
      [_presentingViewController presentViewController:safariVC animated:YES completion:nil];
      return YES;
    }
    openedSafari = [[UIApplication sharedApplication] openURL:requestURL];
  }

  if (!openedSafari) {
    [self cleanUp];
    NSError *safariError = [OIDErrorUtilities errorWithCode:OIDErrorCodeSafariOpenError
                                            underlyingError:nil
                                                description:@"Unable to open Safari."];
    [session failAuthorizationFlowWithError:safariError];
  }
  return openedSafari;
}

- (void)dismissAuthorizationAnimated:(BOOL)animated completion:(void (^)(void))completion {
  if (!_authorizationFlowInProgress) {
    // Ignore this call if there is no authorization flow in progress.
    return;
  }
  SFSafariViewController *safariVC = _safariVC;
  [self cleanUp];
  if (safariVC) {
    [safariVC dismissViewControllerAnimated:YES completion:completion];
  } else {
    if (completion) completion();
  }
}

- (void)cleanUp {
  // The weak references to |_safariVC| and |_session| are set to nil to avoid accidentally using
  // them while not in an authorization flow.
  _safariVC = nil;
  _session = nil;
  _authorizationFlowInProgress = NO;
}

#pragma mark - SFSafariViewControllerDelegate

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
  if (controller != _safariVC) {
    // Ignore this call if the safari view controller do not match.
    return;
  }
  if (!_authorizationFlowInProgress) {
    // Ignore this call if there is no authorization flow in progress.
    return;
  }
  id<OIDAuthorizationFlowSession> session = _session;
  [self cleanUp];
  NSError *error = [OIDErrorUtilities errorWithCode:OIDErrorCodeProgramCanceledAuthorizationFlow
                                    underlyingError:nil
                                        description:nil];
  [session failAuthorizationFlowWithError:error];
}

@end

@implementation OIDDefaultSafariViewControllerFactory

- (SFSafariViewController *)safariViewControllerWithURL:(NSURL *)URL {
  SFSafariViewController *safariViewController =
      [[SFSafariViewController alloc] initWithURL:URL entersReaderIfAvailable:NO];
  return safariViewController;
}

@end

NS_ASSUME_NONNULL_END