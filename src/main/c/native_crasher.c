#include <jni.h>
#include <stdlib.h>

JNIEXPORT void JNICALL Java_com_example_demo_native_NativeCrasher_crashWithAbort
  (JNIEnv *env, jobject obj)
{
    abort();
}

JNIEXPORT jstring JNICALL Java_com_example_demo_native_NativeCrasher_crashWithInvalidFree
  (JNIEnv *env, jobject obj)
{
    int stackVar = 42;
    free(&stackVar);  // Invalid: freeing stack variable causes crash
    return (*env)->NewStringUTF(env, "unreachable");
}

JNIEXPORT jstring JNICALL Java_com_example_demo_native_NativeCrasher_crashWithNullPointer
  (JNIEnv *env, jobject obj)
{
    int *nullPtr = NULL;
    *nullPtr = 42;  // Dereference null pointer causes crash
    return (*env)->NewStringUTF(env, "unreachable");
}
