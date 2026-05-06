// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>

#import "AccountsdBridge.h"
#import <Accounts/Accounts.h>

static NSString *gLastFailureReason = nil;

static void putString(NSMutableDictionary *out, NSString *key, id value) {
    if ([value isKindOfClass:[NSString class]]) {
        if (((NSString *)value).length > 0) out[key] = value;
        return;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        out[key] = [(NSNumber *)value stringValue];
        return;
    }
    if ([value isKindOfClass:[NSData class]]) {
        // best effort: hex-encode small token blobs for diagnostics; long blobs are usually
        // already strings in modern ios versions
        NSData *data = value;
        if (data.length <= 256) {
            NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
            const uint8_t *bytes = data.bytes;
            for (NSUInteger i = 0; i < data.length; i++) [hex appendFormat:@"%02x", bytes[i]];
            out[key] = hex;
        }
    }
}

/// try a list of candidate KVC keys against `obj`, write the first non-empty value into `out[outKey]`
static void tryKeys(id obj, NSArray<NSString *> *keys, NSMutableDictionary *out, NSString *outKey) {
    for (NSString *k in keys) {
        @try {
            id v = [obj valueForKey:k];
            if (v && v != [NSNull null]) {
                putString(out, outKey, v);
                if (out[outKey]) return;
            }
        } @catch (__unused NSException *exc) {
            // KVC throws NSUndefinedKeyException for unknown keys on private classes; ignore and try next
        }
    }
}

static NSDictionary *copyForType(NSString *typeID) {
    Class storeCls = NSClassFromString(@"ACAccountStore");
    if (!storeCls) {
        gLastFailureReason = @"ACAccountStore unavailable";
        return nil;
    }

    ACAccountStore *store = [[storeCls alloc] init];
    ACAccountType *type = [store accountTypeWithAccountTypeIdentifier:typeID];
    if (!type) {
        gLastFailureReason = [NSString stringWithFormat:@"unknown type %@", typeID];
        return nil;
    }

    NSArray<ACAccount *> *accounts = [store accountsWithAccountType:type];
    if (accounts.count == 0) {
        gLastFailureReason = @"no accounts of this type";
        return nil;
    }

    ACAccount *acc = accounts.firstObject;
    NSMutableDictionary *out = [NSMutableDictionary new];

    // Public surface
    if (acc.username.length > 0)   out[@"email"] = acc.username;
    if (acc.identifier.length > 0) out[@"identifier"] = acc.identifier;

    // Private surface — names drift across ios versions, walk candidates
    @try {
        NSDictionary *props = [acc valueForKey:@"properties"];
        if ([props isKindOfClass:[NSDictionary class]]) {
            tryKeys(props, @[@"DSID", @"DSPersonID", @"dsid"],         out, @"dsid");
            tryKeys(props, @[@"AltDSID", @"altDSID"],                  out, @"altDSID");
            tryKeys(props, @[@"storefront", @"Storefront", @"StoreFront"], out, @"storefront");
        }
    } @catch (__unused NSException *exc) {}

    // accountProperties on some ios majors holds the same dict
    if (!out[@"dsid"]) {
        @try {
            NSDictionary *props = [acc valueForKey:@"accountProperties"];
            if ([props isKindOfClass:[NSDictionary class]]) {
                tryKeys(props, @[@"DSID", @"DSPersonID"],          out, @"dsid");
                tryKeys(props, @[@"AltDSID"],                      out, @"altDSID");
                tryKeys(props, @[@"storefront", @"Storefront"],    out, @"storefront");
            }
        } @catch (__unused NSException *exc) {}
    }

    @try {
        ACAccountCredential *cred = acc.credential;
        if (cred.oauthToken.length > 0) out[@"oauthToken"] = cred.oauthToken;
    } @catch (__unused NSException *exc) {}

    return [out copy];
}

@implementation ESAccountsdBridge

+ (BOOL)isAvailable {
    return NSClassFromString(@"ACAccountStore") != nil;
}

+ (NSDictionary *)copyAppleIDAccountInfo {
    NSDictionary *r = copyForType(@"com.apple.account.AppleAccount");
    if (r) gLastFailureReason = nil;
    return r;
}

+ (NSDictionary *)copyiTunesStoreAccountInfo {
    NSDictionary *r = copyForType(@"com.apple.account.iTunesStore");
    if (r) gLastFailureReason = nil;
    return r;
}

+ (NSString *)lastFailureReason {
    return gLastFailureReason;
}

@end
