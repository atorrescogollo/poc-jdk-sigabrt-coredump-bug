package com.example.demo.native

import java.io.File
import java.nio.file.Files

object LibraryLoader {
    fun load() {
        val osName = System.getProperty("os.name").lowercase()
        val libraryName = when {
            osName.contains("mac") || osName.contains("darwin") -> "libnativecrasher.dylib"
            osName.contains("linux") -> "libnativecrasher.so"
            else -> throw UnsupportedOperationException("Unsupported OS: $osName")
        }

        val resourceStream = LibraryLoader::class.java.classLoader.getResourceAsStream(libraryName)
            ?: throw RuntimeException("Native library not found in classpath: $libraryName")

        val tempFile = Files.createTempFile("libnativecrasher", if (libraryName.endsWith(".dylib")) ".dylib" else ".so").toFile()
        tempFile.deleteOnExit()

        resourceStream.use { input ->
            tempFile.outputStream().use { output ->
                input.copyTo(output)
            }
        }

        System.load(tempFile.absolutePath)
    }
}
