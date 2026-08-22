#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <unistd.h>

static void (*OriginalMSHookMessageEx)(Class, SEL, IMP, IMP *);
extern "C" __attribute__((visibility("default"))) char PBWProbeLog[4096];
char PBWProbeLog[4096];
static size_t ProbeLogLength;
static const char *const kProbeLogPath = "/var/mobile/Library/Caches/pbw-hook-probe.log";

static void PersistProbeLog(void) {
    int descriptor = open(kProbeLogPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (descriptor < 0) return;
    (void)write(descriptor, PBWProbeLog, ProbeLogLength);
    (void)close(descriptor);
}

static void AppendProbeLine(const char *format, ...) {
    if (ProbeLogLength >= sizeof(PBWProbeLog) - 1) return;
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(PBWProbeLog + ProbeLogLength, sizeof(PBWProbeLog) - ProbeLogLength, format, arguments);
    va_end(arguments);
    if (length <= 0) return;
    size_t available = sizeof(PBWProbeLog) - ProbeLogLength;
    ProbeLogLength += (size_t)length < available ? (size_t)length : available - 1;
    PersistProbeLog();
}

static void WriteProbeLine(Class targetClass, SEL selector, IMP replacement, IMP *original) {
    const char *className = targetClass ? class_getName(targetClass) : "<nil>";
    const char *selectorName = selector ? sel_getName(selector) : "<nil>";
    AppendProbeLine(
        "class=%s selector=%s replacement=%p originalSlot=%p\n",
        className ?: "<null>",
        selectorName ?: "<null>",
        replacement,
        original
    );
}

static void WriteProbeStatus(const char *status, const void *value) {
    AppendProbeLine("status=%s value=%p\n", status, value);
}

static bool IsPBWallpaperCaller(void *returnAddress) {
    Dl_info image = {};
    return dladdr(returnAddress, &image) != 0 && image.dli_fname != nullptr && strstr(image.dli_fname, "PBWallpaper.dylib") != nullptr;
}

static void ProbeMSHookMessageEx(Class targetClass, SEL selector, IMP replacement, IMP *original) {
    if (IsPBWallpaperCaller(__builtin_return_address(0))) {
        WriteProbeLine(targetClass, selector, replacement, original);
    }
    OriginalMSHookMessageEx(targetClass, selector, replacement, original);
}

%ctor {
    WriteProbeStatus("constructor", (const void *)MSHookMessageEx);
    MSHookFunction(
        (void *)MSHookMessageEx,
        (void *)ProbeMSHookMessageEx,
        (void **)&OriginalMSHookMessageEx
    );
    WriteProbeStatus("hookedOriginal", (const void *)OriginalMSHookMessageEx);
}
