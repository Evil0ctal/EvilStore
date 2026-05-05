// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin objc wrapper around ACAccountStore + private KVC.
/// Keeps the unsafe valueForKey: out of swift so we get @try/@catch around
/// per-version property name drift.
///
/// Output dict keys (any may be missing on a given ios version):
///   email      : NSString
///   identifier : NSString  (account uuid)
///   dsid       : NSString
///   altDSID    : NSString
///   storefront : NSString  (raw, e.g. "143441-19,29")
///   oauthToken : NSString
@interface ESAccountsdBridge : NSObject

+ (BOOL)isAvailable;

/// returns nil on failure; reason is captured in `lastFailureReason`
+ (nullable NSDictionary<NSString *, NSString *> *)copyAppleIDAccountInfo;

/// returns nil on failure; reason is captured in `lastFailureReason`
+ (nullable NSDictionary<NSString *, NSString *> *)copyiTunesStoreAccountInfo;

/// human-readable reason for the most recent nil return
@property (class, readonly, copy, nullable) NSString *lastFailureReason;

@end

NS_ASSUME_NONNULL_END
