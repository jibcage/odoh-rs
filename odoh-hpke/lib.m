//
//  lib.m
//  odoh-hpke
//
//  Created by Jack Kim-Biggs on 11/8/21.
//


#include "odoh-rs.h"
#include "odoh_hpke.h"
#import <Foundation/Foundation.h>

@implementation HPKEBridge
+ (void *)contextWithData:(NSData *)odohConfigs {
    void *ctx = NULL;
    if (!odoh_create_context(&ctx, odohConfigs.bytes, odohConfigs.length)) {
        return NULL;
    }
    return ctx;
}

+ (NSData *)encryptQuery:(NSData *)query
             withContext:(void *)context
           withSecretPtr:(NSData * _Nonnull __autoreleasing *)secretOut
{
    uint8_t *bytes = NULL;
    size_t len = 0;
    OdohSecret client_secret = {};

    if (!odoh_encrypt_query(&bytes,
                            &len,
                            &client_secret,
                            query.bytes,
                            query.length,
                            context))
    {
        return NULL;
    }

    *secretOut = [NSData dataWithBytes:&client_secret length:sizeof(OdohSecret)];
    return [NSData dataWithBytesNoCopy:bytes length:len freeWhenDone:true];
}

+ (NSData *)decryptResponse:(NSData *)encryptedResponse
                 withSecret:(NSData *)secret
              originalQuery:(NSData *)query
{
    uint8_t *bytes = NULL;
    size_t len = 0;

    if (!odoh_decrypt_response(&bytes,
                               &len,
                               query.bytes,
                               query.length,
                               encryptedResponse.bytes,
                               encryptedResponse.length,
                               secret.bytes))
    {
        return NULL;
    }
    return [NSData dataWithBytesNoCopy:bytes length:len freeWhenDone:true];
}
@end
