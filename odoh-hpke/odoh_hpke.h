//
//  odoh_hpke.h
//  odoh-hpke
//
//  Created by Jack Kim-Biggs on 11/8/21.
//

#import <Foundation/Foundation.h>

//! Project version number for odoh_hpke.
FOUNDATION_EXPORT double odoh_hpkeVersionNumber;

//! Project version string for odoh_hpke.
FOUNDATION_EXPORT const unsigned char odoh_hpkeVersionString[];

@interface HPKEBridge: NSObject
+ (void * _Nullable)contextWithData:(NSData * _Nonnull)odohConfigs;
+ (NSData * _Nullable)encryptQuery:(NSData * _Nonnull)query withContext:(void * _Nonnull)context withSecretPtr:(NSData * _Nonnull * _Nonnull)secretOut;
+ (NSData * _Nullable)decryptResponse:(NSData * _Nonnull)encryptedResponse withSecret:(NSData * _Nonnull)secret originalQuery:(NSData * _Nonnull)query;
@end
