package com.litter.android.state

import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.nio.file.Files

class LocalWorkspaceFilesTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test fun createsEditsRenamesAndDeletesText() {
        val root = temporary.newFolder("root")
        val files = LocalWorkspaceFiles(root)
        files.create(root, "hello.txt", false)
        val file = File(root, "hello.txt")
        files.write(file, "Alley Cåt")
        assertEquals("Alley Cåt", files.read(file))
        files.rename(file, "renamed.txt")
        assertEquals(listOf("renamed.txt"), files.list(root).map { it.name })
        files.delete(File(root, "renamed.txt"))
        assertTrue(files.list(root).isEmpty())
    }

    @Test fun rejectsTraversalAndOutsideSymlinks() {
        val root = temporary.newFolder("root")
        val outside = temporary.newFolder("outside")
        val files = LocalWorkspaceFiles(root)
        assertThrows(IllegalArgumentException::class.java) { files.child(root, "../outside") }
        assertThrows(IllegalArgumentException::class.java) { files.checked(outside) }
        val link = File(root, "link")
        Files.createSymbolicLink(link.toPath(), outside.toPath())
        assertThrows(IllegalArgumentException::class.java) { files.checked(link) }
        assertThrows(IllegalArgumentException::class.java) { files.delete(root) }
        assertTrue(outside.exists())
    }

    @Test fun rejectsBinaryAndLargeFilesAndDeletesNonemptyFolders() {
        val root = temporary.newFolder("root")
        val files = LocalWorkspaceFiles(root)
        val binary = File(root, "binary").apply { writeBytes(byteArrayOf(0, 1)) }
        assertThrows(IllegalArgumentException::class.java) { files.read(binary) }
        val large = File(root, "large").apply { writeBytes(ByteArray(2 * 1024 * 1024 + 1) { 65 }) }
        assertThrows(IllegalArgumentException::class.java) { files.read(large) }
        val folder = File(root, "folder").apply { mkdir() }
        File(folder, "keep").writeText("keep")
        files.delete(folder)
        assertFalse(folder.exists())
    }

    @Test fun deletingSymlinkDoesNotDeleteItsTarget() {
        val root = temporary.newFolder("root")
        val outside = temporary.newFolder("outside")
        File(outside, "keep").writeText("keep")
        val link = File(root, "link")
        Files.createSymbolicLink(link.toPath(), outside.toPath())
        LocalWorkspaceFiles(root).delete(link)
        assertFalse(Files.exists(link.toPath(), java.nio.file.LinkOption.NOFOLLOW_LINKS))
        assertEquals("keep", File(outside, "keep").readText())
    }

    @Test fun refusesDanglingDestinationAndProtectedFolders() {
        val root = temporary.newFolder("root")
        val files = LocalWorkspaceFiles(root)
        val source = File(root, "source").apply { writeText("keep") }
        Files.createSymbolicLink(File(root, "target").toPath(), File(root, "missing").toPath())
        assertThrows(IllegalArgumentException::class.java) { files.rename(source, "target") }
        assertEquals("keep", source.readText())
        val protected = File(root, "etc").apply { mkdir() }
        assertThrows(IllegalArgumentException::class.java) { files.delete(protected) }
        assertTrue(protected.exists())
    }
}
