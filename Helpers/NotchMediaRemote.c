#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

typedef unsigned char Boolean;
typedef Boolean (*MRMediaRemoteSendCommandFunc)(int command, const void *userInfo);

__attribute__((visibility("default")))
void notch_send_media_command(void) {
    const char *raw = getenv("NOTCH_MEDIA_COMMAND");
    int command = raw ? atoi(raw) : 2;

    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_LAZY
    );
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
