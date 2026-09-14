#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef Boolean (*MRMediaRemoteSendCommandFunc)(int command, const void *userInfo);
typedef void (*MRMediaRemoteGetNowPlayingInfoFunc)(dispatch_queue_t queue, void (^handler)(id info));

static void *mediaRemoteHandle(void) {
    return dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_LAZY
    );
}

static NSData *artworkFromInfo(id info, void *handle) {
    if (![info isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *dict = (NSDictionary *)info;

    CFStringRef *keyPtr = (CFStringRef *)dlsym(handle, "kMRMediaRemoteNowPlayingInfoArtworkData");
    if (keyPtr && *keyPtr) {
        id value = [dict objectForKey:(__bridge id)(*keyPtr)];
        if ([value isKindOfClass:[NSData class]] && [(NSData *)value length] > 32) {
            return value;
        }
    }

    id named = dict[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    if ([named isKindOfClass:[NSData class]] && [(NSData *)named length] > 32) {
        return named;
    }

    for (id key in dict) {
        id value = dict[key];
        if (![value isKindOfClass:[NSData class]] || [(NSData *)value length] <= 32) {
            continue;
        }
        NSString *name = [key description].lowercaseString;
        if ([name containsString:@"artwork"]) {
            return value;
        }
    }
    return nil;
}

__attribute__((visibility("default")))
void notch_send_media_command(void) {
    const char *raw = getenv("NOTCH_MEDIA_COMMAND");
    int command = raw ? atoi(raw) : 2;

    void *handle = mediaRemoteHandle();
    if (!handle) {
        return;
    }

    MRMediaRemoteSendCommandFunc send = (MRMediaRemoteSendCommandFunc)dlsym(
        handle,
        "MRMediaRemoteSendCommand"
    );
    if (!send) {
        return;
    }

    send(command, NULL);
    // Delivery is asynchronous; keep the entitled process alive briefly.
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.35, false);
}

__attribute__((visibility("default")))
void notch_get_artwork(void) {
    void *handle = mediaRemoteHandle();
    if (!handle) {
        return;
    }

    MRMediaRemoteGetNowPlayingInfoFunc getInfo = (MRMediaRemoteGetNowPlayingInfoFunc)dlsym(
        handle,
        "MRMediaRemoteGetNowPlayingInfo"
    );
    if (!getInfo) {
        return;
    }

    __block NSData *artwork = nil;
    __block BOOL done = NO;

    // MediaRemote gathers info on the main run loop. Blocking it with a
    // semaphore makes the callback never fire (common for Spotify covers).
    getInfo(dispatch_get_main_queue(), ^(id info) {
        artwork = artworkFromInfo(info, handle);
        done = YES;
        CFRunLoopStop(CFRunLoopGetMain());
    });

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.5];
    while (!done && [deadline timeIntervalSinceNow] > 0) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
    }

    if (artwork.length == 0) {
        return;
    }

    NSString *b64 = [artwork base64EncodedStringWithOptions:0];
    const char *utf8 = b64.UTF8String;
    if (!utf8) {
        return;
    }
    fputs(utf8, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}
