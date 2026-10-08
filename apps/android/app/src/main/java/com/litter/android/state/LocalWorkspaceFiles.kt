package com.litter.android.state

import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.FileVisitResult
import java.nio.file.attribute.BasicFileAttributes
import java.nio.file.StandardCopyOption

/** Android's app-private proot filesystem; canonical checks exclude host links. */
class LocalWorkspaceFiles(rootDirectory: File) {
    val root: File = rootDirectory.canonicalFile

    fun checked(file: File): File {
        val canonical = file.canonicalFile
        require(canonical == root || canonical.path.startsWith(root.path + File.separator)) {
            "This path leaves the local workspace."
        }
        return canonical
    }

    fun child(parent: File, name: String): File {
        require(name.isNotBlank() && name != "." && name != ".." && !name.contains('/') && !name.contains('\\')) { "Enter a single file or folder name." }
        return entry(File(checked(parent), name))
    }

    private fun entry(file: File): File {
        val path = file.absoluteFile.toPath().normalize().toFile()
        require(path != root && path.path.startsWith(root.path + File.separator)) { "The workspace root cannot be changed." }
        checked(path.parentFile!!)
        return path
    }

    private fun exists(file: File) = Files.exists(file.toPath(), LinkOption.NOFOLLOW_LINKS)

    fun list(directory: File): List<File> {
        val dir = checked(directory)
        require(dir.isDirectory) { "Folder unavailable. Start the local runtime first." }
        return (dir.listFiles() ?: error("Could not read this folder.")).sortedWith(compareBy<File> { !it.isDirectory }.thenBy { it.name.lowercase() })
    }

    fun read(file: File): String {
        val path = checked(file)
        require(path.isFile && path.length() <= 2 * 1024 * 1024) { "Only text files up to 2 MB can be edited here." }
        val bytes = path.inputStream().use { input ->
            val buffer = ByteArray(2 * 1024 * 1024 + 1)
            var used = 0
            while (used < buffer.size) {
                val count = input.read(buffer, used, buffer.size - used)
                if (count < 0) break
                used += count
            }
            buffer.copyOf(used)
        }
        require(bytes.size <= 2 * 1024 * 1024 && bytes.none { it == 0.toByte() }) { "This file is binary or too large." }
        return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
    }

    fun write(file: File, text: String) {
        val path = checked(file)
        require(path != root && text.toByteArray().size <= 2 * 1024 * 1024) { "File is too large." }
        val tmp = File.createTempFile(".alleycat-", ".tmp", path.parentFile!!)
        try {
            tmp.writeText(text)
            if (path.exists()) {
                Files.setPosixFilePermissions(tmp.toPath(), Files.getPosixFilePermissions(path.toPath()))
            }
            // Same-directory replacement; failure leaves the previous file intact.
            Files.move(tmp.toPath(), path.toPath(), StandardCopyOption.REPLACE_EXISTING)
        } finally { tmp.delete() }
    }

    fun create(directory: File, name: String, folder: Boolean) {
        val path = child(directory, name)
        check(if (folder) path.mkdir() else path.createNewFile()) { "Item already exists or cannot be created." }
    }

    fun rename(file: File, name: String) {
        val source = entry(file)
        val target = child(source.parentFile!!, name)
        require(!exists(target)) { "That name already exists." }
        Files.move(source.toPath(), target.toPath())
    }

    fun move(file: File, guestDirectory: String) {
        val source = entry(file)
        val destination = checked(File(root, guestDirectory.trimStart('/')))
        require(destination.isDirectory) { "Choose an existing destination folder." }
        val target = child(destination, source.name)
        require(!exists(target)) { "The destination already contains this name." }
        Files.move(source.toPath(), target.toPath())
    }

    fun importFile(directory: File, name: String, input: java.io.InputStream) {
        val target = child(directory, name)
        require(!exists(target)) { "A file with this name already exists." }
        val tmp = File.createTempFile(".alleycat-", ".tmp", checked(directory))
        try {
            tmp.outputStream().use { output ->
                val buffer = ByteArray(8192)
                var total = 0L
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    total += count
                    require(total <= 64 * 1024 * 1024) { "Import files up to 64 MB." }
                    output.write(buffer, 0, count)
                }
            }
            Files.move(tmp.toPath(), target.toPath())
        } finally { tmp.delete() }
    }

    fun exportFile(file: File, output: java.io.OutputStream) {
        val source = checked(file)
        require(source.isFile) { "Select a file to export." }
        source.inputStream().use { it.copyTo(output, 8192) }
    }

    fun delete(file: File) {
        val path = entry(file)
        val relative = path.relativeTo(root).invariantSeparatorsPath
        require(relative !in setOf("root", "usr", "etc", "bin", "sbin", "lib", "dev", "mnt", "root/.codex")) {
            "This filesystem location is protected."
        }
        if (!exists(path)) return
        // walkFileTree does not follow symlinks without FOLLOW_LINKS.
        Files.walkFileTree(path.toPath(), object : SimpleFileVisitor<Path>() {
            override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                Files.delete(file)
                return FileVisitResult.CONTINUE
            }
            override fun postVisitDirectory(dir: Path, error: java.io.IOException?): FileVisitResult {
                if (error != null) throw error
                Files.delete(dir)
                return FileVisitResult.CONTINUE
            }
        })
    }
}
