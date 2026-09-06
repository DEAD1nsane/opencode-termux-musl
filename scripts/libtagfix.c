// libtagfix.c — disable Android's heap tagging before JavaScriptCore initializes.
//
// On Android 11+, bionic tags heap pointers with the top byte (TBI / MTE).
// JSC's NaN-boxing representation clobbers that tag byte, and on free()
// bionic sees a tag mismatch and aborts with "Pointer tag ... was truncated".
//
// This library is LD_PRELOAD'd by the wrapper. The init constructor runs
// before main(), so by the time JSC initializes, heap tagging is already off.
//
// Only the mallopt call is needed — the rest is plumbing to make the
// constructor survive across forks and to silence "unused" warnings.
//
// Build:
//   $PREFIX/bin/clang -shared -fPIC -nostdlib -static-libcwu \
//       -Wl,-z,nodelete -Wl,--build-id=sha1 \
//       -o libtagfix.so libtagfix.c
//   (the Termux NDK clang produces a binary that runs on Android/Bionic)

#include <malloc.h>

/* mallopt() is a private Bionic API. Declare it locally; the constants
 * below are also private (M_HEAP_TAGGING_LEVEL_NONE happens to be exposed
 * in recent Bionic, M_BIONIC_SET_HEAP_TAGGING_LEVEL is not). */
extern int mallopt(int, int);

#ifndef M_BIONIC_SET_HEAP_TAGGING_LEVEL
#define M_BIONIC_SET_HEAP_TAGGING_LEVEL (-204)
#endif

__attribute__((constructor(101)))
static void disable_heap_tagging(void) {
    mallopt(M_BIONIC_SET_HEAP_TAGGING_LEVEL, M_HEAP_TAGGING_LEVEL_NONE);
}
