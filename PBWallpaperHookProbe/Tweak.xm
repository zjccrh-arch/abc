#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

static void (*OriginalMSHookMessageEx)(Class, SEL, IMP, IMP *);

static void WriteProbeLine(Class targetClass, SEL selector, IMP replacement, IMP *original) {
    char line[768];
    const char *className = targetClass ? class_getName(targetClass) : "<nil>";
    const char *selectorName = selector ? sel_getName(selector) : "<nil>";
    int length = snprintf(
        line,
        sizeof(line),
        "class=%s selector=%s replacement=%p originalSlot=%p\n",
        className ?: "<null>",
        selectorName ?: "<null>",
        replacement,
        original
    );
    if (length <= 0) return;
    int fd = open("/var/mobile/pbw-hook-probe.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    write(fd, line, (size_t)length);
    close(fd);
}

static void WriteProbeStatus(const char *status, const void *value) {
    char line[256];
    int length = snprintf(line, sizeof(line), "status=%s value=%p\n", status, value);
    if (length <= 0) return;
    int fd = open("/var/mobile/pbw-hook-probe.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    write(fd, line, (size_t)length);
    close(fd);
}

static void ProbeMSHookMessageEx(Class targetClass, SEL selector, IMP replacement, IMP *original) {
    WriteProbeLine(targetClass, selector, replacement, original);
    OriginalMSHookMessageEx(targetClass, selector, replacement, original);
}

%ctor {
    unlink("/var/mobile/pbw-hook-probe.log");
    WriteProbeStatus("constructor", (const void *)MSHookMessageEx);
    MSHookFunction(
        (void *)MSHookMessageEx,
        (void *)ProbeMSHookMessageEx,
        (void **)&OriginalMSHookMessageEx
    );
    WriteProbeStatus("hookedOriginal", (const void *)OriginalMSHookMessageEx);
}
