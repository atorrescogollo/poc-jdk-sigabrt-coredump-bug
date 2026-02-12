package com.example.demo.controller

import com.example.demo.native.NativeCrasher
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController
import sun.misc.Unsafe

@RestController
@RequestMapping("/crash")
class CrashController {

    @GetMapping("/free")
    fun crashWithFree(): String {
        return NativeCrasher.crashWithInvalidFree()
    }

    @GetMapping("/null")
    fun crashWithNull(): String {
        return NativeCrasher.crashWithNullPointer()
    }

    @GetMapping("/unsafe")
    fun crashWithUnsafe(): String {
        val unsafeField = Unsafe::class.java.getDeclaredField("theUnsafe")
        unsafeField.isAccessible = true
        val unsafe = unsafeField.get(null) as Unsafe
        unsafe.putAddress(0, 0)
        return "unreachable"
    }
}
