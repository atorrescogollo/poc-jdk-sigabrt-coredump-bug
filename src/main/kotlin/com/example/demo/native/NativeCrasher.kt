package com.example.demo.native

object NativeCrasher {
    init {
        LibraryLoader.load()
    }

    external fun crashWithAbort(): String
    external fun crashWithInvalidFree(): String
    external fun crashWithNullPointer(): String
}
