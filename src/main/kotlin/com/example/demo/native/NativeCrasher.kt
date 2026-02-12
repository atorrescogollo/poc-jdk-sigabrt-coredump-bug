package com.example.demo.native

object NativeCrasher {
    init {
        LibraryLoader.load()
    }

    external fun crashWithInvalidFree(): String
    external fun crashWithNullPointer(): String
}
