// libresolvefix.c — redirect musl's /etc/resolv.conf reads to Termux's path.
//
// Musl's resolver reads /etc/resolv.conf, but Android's /etc is read-only.
// Termux stores its resolv.conf at $PREFIX/etc/resolv.conf. This LD_PRELOAD
// shim intercepts open() and fopen() calls for /etc/resolv.conf and redirects
// them to the Termux path.
//
// Build:
//   clang -shared -fPIC -o libresolvefix.so libresolvefix.c
//
// Usage:
//   LD_PRELOAD=libresolvefix.so <binary>

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <stdarg.h>

static const char *RESOLV_CONF = "/etc/resolv.conf";
static const char *TERMUX_RESOLV = "/data/data/com.termux/files/usr/etc/resolv.conf";

static const char *redirect(const char *p) {
    return (p && strcmp(p, RESOLV_CONF) == 0) ? TERMUX_RESOLV : p;
}

int open(const char *pathname, int flags, ...) {
    int (*real_open)(const char *, int, ...) = dlsym(RTLD_NEXT, "open");
    const char *p = redirect(pathname);
    if (flags & (O_CREAT | O_TMPFILE)) {
        va_list ap;
        va_start(ap, flags);
        mode_t m = va_arg(ap, mode_t);
        va_end(ap);
        return real_open(p, flags, m);
    }
    return real_open(p, flags);
}

FILE *fopen(const char *pathname, const char *mode) {
    FILE *(*real_fopen)(const char *, const char *) = dlsym(RTLD_NEXT, "fopen");
    return real_fopen(redirect(pathname), mode);
}
