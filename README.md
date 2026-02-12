# OpenJDK HotSpot SIGABRT Signal Handling Issue - PoC

This repository demonstrates a critical issue with OpenJDK HotSpot's signal handling: **SIGABRT signals are not caught by the JVM**, preventing core dumps from being generated when native libraries encounter memory management errors.

## The Problem

When native code calls `abort()` (typically due to memory corruption detected by glibc), the process crashes without generating a core dump, even when using `-XX:+CreateCoredumpOnCrash`. This occurs because HotSpot does not register a handler for SIGABRT.

### Why This Is Critical

In production environments, this means:

- Memory corruption bugs in native libraries crash without diagnostic artifacts
- Intermittent crashes are nearly impossible to debug
- No core dumps = no post-mortem analysis

HotSpot handles signals like `SIGSEGV`, `SIGBUS`, `SIGFPE`, and `SIGILL`, but **NOT SIGABRT**.

Reference: [signals_posix.cpp:1352-1358](https://github.com/openjdk/jdk/blob/37dc1be67d4c15a040dc99dbc105c3269c65063d/src/hotspot/os/posix/signals_posix.cpp#L1352-L1358)

## What This PoC Demonstrates

This Spring Boot application provides three REST endpoints that trigger different types of crashes to demonstrate the inconsistency:

1. **`/crash/unsafe`** - Java Unsafe memory access → SIGSEGV → ✅ **Core dump created**
2. **`/crash/null`** - Native null pointer dereference → SIGSEGV → ✅ **Core dump created**
3. **`/crash/free`** - Native invalid free() → SIGABRT → ❌ **NO core dump (THE BUG)**

## Prerequisites

- Docker and Docker Compose
- curl or any HTTP client

## Quick Start

```bash
# Clone the repository
git clone https://github.com/atorrescogollo/poc-jdk-sigtrap-coredump-handling.git
cd poc-jdk-sigtrap-coredump-handling

# Start the application
docker-compose up -d

# Wait for startup (check logs)
docker-compose logs -f
# Wait until you see "Started DemoApplicationKt"
```

## Reproducing the Issue

### Test 1: Unsafe Memory Access (Works as Expected)

This test uses Java's `Unsafe` class to write to memory address 0, triggering a segmentation fault.

```bash
# Start fresh
docker-compose up -d

# Trigger the crash
curl localhost:8080/crash/unsafe

# Check the logs
docker-compose logs
```

**Expected output:**

```
#
# A fatal error has been detected by the Java Runtime Environment:
#
#  SIGSEGV (0xb) at pc=0x0000ffffb05ae9f4, pid=1, tid=43
#
# JRE version: OpenJDK Runtime Environment Corretto-25.0.2.10.1 (25.0.2+10) (build 25.0.2+10-LTS)
# Java VM: OpenJDK 64-Bit Server VM Corretto-25.0.2.10.1 (25.0.2+10-LTS, mixed mode, sharing, tiered, compressed oops, compressed class ptrs, g1 gc, linux-aarch64)
# Problematic frame:
# V  [libjvm.so+0xf4b9f4]  Unsafe_PutLong+0xb4
#
# An error report file with more information is saved as:
# /core-dumps/hs_err_pid1.log
```

✅ **Result:** Error report generated, JVM caught the signal

**Code (src/main/kotlin/com/example/demo/controller/CrashController.kt:24-30):**

```kotlin
@GetMapping("/unsafe")
fun crashWithUnsafe(): String {
    val unsafeField = Unsafe::class.java.getDeclaredField("theUnsafe")
    unsafeField.isAccessible = true
    val unsafe = unsafeField.get(null) as Unsafe
    unsafe.putAddress(0, 0)
    return "unreachable"
}
```

### Test 2: Native Null Pointer Dereference (Works as Expected)

This test uses JNI native code to dereference a null pointer, also triggering a segmentation fault.

```bash
# Restart the service
docker-compose restart

# Trigger the crash
curl localhost:8080/crash/null

# Check the logs
docker-compose logs
```

**Expected output:**

```
#
# A fatal error has been detected by the Java Runtime Environment:
#
#  SIGSEGV (0xb) at pc=0x0000fffebf3591c8, pid=1, tid=42
#
# JRE version: OpenJDK Runtime Environment Corretto-25.0.2.10.1 (25.0.2+10) (build 25.0.2+10-LTS)
# Java VM: OpenJDK 64-Bit Server VM Corretto-25.0.2.10.1 (25.0.2+10-LTS, mixed mode, sharing, tiered, compressed oops, compressed class ptrs, g1 gc, linux-aarch64)
# Problematic frame:
# C  [libnativecrasher.so+0x101c8]  Java_com_example_demo_native_NativeCrasher_crashWithNullPointer+0x1c
#
# An error report file with more information is saved as:
# /core-dumps/hs_err_pid1.log
# The crash happened outside the Java Virtual Machine in native code.
```

✅ **Result:** Error report generated, JVM caught the signal

**Code (src/main/c/native_crasher.c:12-18):**

```c
JNIEXPORT jstring JNICALL Java_com_example_demo_native_NativeCrasher_crashWithNullPointer
  (JNIEnv *env, jobject obj)
{
    int *nullPtr = NULL;
    *nullPtr = 42;  // Dereference null pointer causes SIGSEGV
    return (*env)->NewStringUTF(env, "unreachable");
}
```

### Test 3: Invalid free() Call - THE BUG

This test demonstrates the actual issue: native code attempts to free a stack variable, causing glibc to detect the error and call `abort()`, which raises SIGABRT.

```bash
# Restart the service
docker-compose restart

# Trigger the crash
curl localhost:8080/crash/free

# Check the logs
docker-compose logs
```

**Expected output:**

```
munmap_chunk(): invalid pointer
```

Or when using tcmalloc:

```
src/tcmalloc.cc:333] Attempt to free invalid pointer 0xffff38000b60
```

❌ **Result:**

- Process exits immediately
- **NO error report file generated**
- **NO core dump created**
- No JVM signal handler invoked

**Code (src/main/c/native_crasher.c:4-10):**

```c
JNIEXPORT jstring JNICALL Java_com_example_demo_native_NativeCrasher_crashWithInvalidFree
  (JNIEnv *env, jobject obj)
{
    int stackVar = 42;
    free(&stackVar);  // Invalid: freeing stack variable causes glibc to abort()
    return (*env)->NewStringUTF(env, "unreachable");
}
```

**Code (src/main/kotlin/com/example/demo/controller/CrashController.kt:13-16):**

```kotlin
@GetMapping("/free")
fun crashWithFree(): String {
    return NativeCrasher.crashWithInvalidFree()
}
```

### Verifying Core Dumps

After each test, you can check if core dumps were created:

```bash
# Check core dumps directory
ls -lh core-dumps/

# View error report files
cat core-dumps/hs_err_pid*.log
```

For tests 1 and 2, you should see `hs_err_pid*.log` files. For test 3, you won't.

## What's Different?

| Test                 | Signal      | Core Dump? | Error Report? |
| -------------------- | ----------- | ---------- | ------------- |
| Unsafe memory access | SIGSEGV     | ✅         | ✅            |
| Native null pointer  | SIGSEGV     | ✅         | ✅            |
| Invalid free()       | **SIGABRT** | ❌         | ❌            |

The critical difference is the signal type. HotSpot handles SIGSEGV but not SIGABRT.

## Project Structure

```
src/
├── main/
│   ├── kotlin/com/example/demo/
│   │   ├── DemoApplication.kt               # Spring Boot main
│   │   ├── controller/
│   │   │   └── CrashController.kt          # REST endpoints for crash tests
│   │   └── native/
│   │       ├── NativeCrasher.kt            # JNI interface declarations
│   │       └── LibraryLoader.kt            # Loads native library at runtime
│   └── c/
│       └── native_crasher.c                # Native code with intentional crashes
├── docker-compose.yml                       # Service configuration
├── Dockerfile                               # Multi-stage build with GCC
└── build.gradle                             # Kotlin + native compilation
```

## Configuration

The JVM is configured via `docker-compose.yml`:

```yaml
environment:
  - JAVA_TOOL_OPTIONS=-XX:+CreateCoredumpOnCrash -XX:ErrorFile=/core-dumps/hs_err_pid%p.log
```

Core dumps and error reports are written to `./core-dumps/`, which is mounted as a Docker volume.

## Real-World Impact

This issue affects production Java applications that use native libraries. Common scenarios include:

- Memory allocators (jemalloc, tcmalloc) detecting heap corruption
- Native libraries with memory bugs (buffer overflows, double free, use-after-free)
- JNI code with pointer errors
- Third-party native dependencies

When these issues occur randomly in production, the lack of core dumps makes root cause analysis extremely difficult or impossible.

## Cleanup

```bash
# Stop and remove containers
docker-compose down

# Clean up core dumps
rm -rf core-dumps/*
```

## Technical Details

### Why SIGABRT Isn't Handled

Looking at the HotSpot source code in `signals_posix.cpp`, the signal handlers are installed for:

```c
set_signal_handler(SIGSEGV);
set_signal_handler(SIGPIPE);
set_signal_handler(SIGBUS);
set_signal_handler(SIGILL);
set_signal_handler(SIGFPE);
set_signal_handler(SIGXFSZ);
// ... but NOT SIGABRT
```

When glibc's malloc implementation detects corruption, it calls `abort()`, which raises SIGABRT. Since there's no handler, the default behavior occurs (immediate termination without core dump).

## References

- [OpenJDK signals_posix.cpp](https://github.com/openjdk/jdk/blob/master/src/hotspot/os/posix/signals_posix.cpp)
- [OpenJDK os_posix.cpp](https://github.com/openjdk/jdk/blob/master/src/hotspot/os/posix/os_posix.cpp)

## Author

Álvaro Torres Cogollo

## License

This project is provided as-is for demonstration and bug reporting purposes.
