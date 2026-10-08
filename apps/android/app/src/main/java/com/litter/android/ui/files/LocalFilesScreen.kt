package com.litter.android.ui.files

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import android.provider.OpenableColumns
import kotlinx.coroutines.CancellationException
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.litter.android.state.AndroidProotBootstrap
import com.litter.android.state.LocalWorkspaceFiles
import com.litter.android.ui.LitterTheme
import com.litter.android.ui.tv.TvButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

@Composable
fun LocalFilesScreen(onBack: () -> Unit, onTerminal: (String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val bootstrap by AndroidProotBootstrap.state.collectAsState()
    if (bootstrap.status != AndroidProotBootstrap.Status.Ready) {
        Column(Modifier.fillMaxSize().padding(32.dp)) {
            TvButton("Back", onBack)
            Text(bootstrap.message ?: "Preparing the local filesystem…", color = LitterTheme.textPrimary)
        }
        return
    }
    val files = remember(bootstrap.status) {
        val extracted = File(context.filesDir, "proot/alpine-rootfs")
        val root = File(extracted, "fs/data").takeIf { File(it, "bin/sh").exists() } ?: extracted
        LocalWorkspaceFiles(root)
    }
    var directory by remember { mutableStateOf(File(files.root, "root").takeIf { it.isDirectory } ?: files.root) }
    var entries by remember { mutableStateOf<List<File>>(emptyList()) }
    var selected by remember { mutableStateOf<File?>(null) }
    var text by remember { mutableStateOf("") }
    var baseline by remember { mutableStateOf("") }
    var importDirectory by remember { mutableStateOf<File?>(null) }
    var editing by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var action by remember { mutableStateOf<String?>(null) }
    var name by remember { mutableStateOf("") }
    fun perform(onSuccess: () -> Unit = {}, block: () -> Unit) {
        if (busy) return
        val operationDirectory = directory
        busy = true
        scope.launch {
            try {
                withContext(Dispatchers.IO) { block() }
                entries = withContext(Dispatchers.IO) { files.list(operationDirectory) }
                selected = selected?.takeIf { it.exists() || java.nio.file.Files.isSymbolicLink(it.toPath()) }
                onSuccess()
                error = null
            } catch (e: CancellationException) { throw e }
            catch (e: Exception) { error = e.message ?: "File operation failed." }
            finally { busy = false }
        }
    }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        val destination = importDirectory
        importDirectory = null
        if (uri != null && destination != null) perform {
            val displayName = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            } ?: "imported-file"
            context.contentResolver.openInputStream(uri)?.use { files.importFile(destination, displayName, it) }
                ?: throw IllegalStateException("Could not read the selected file.")
        }
    }
    var exportSource by remember { mutableStateOf<File?>(null) }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        val source = exportSource
        exportSource = null
        if (uri != null && source != null) perform {
            context.contentResolver.openOutputStream(uri)?.use { files.exportFile(source, it) }
                ?: throw IllegalStateException("Could not write the exported file.")
        }
    }
    LaunchedEffect(directory) {
        try { entries = withContext(Dispatchers.IO) { files.list(directory) }; error = null }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) { error = e.message }
    }
    Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            TvButton("Back", { if (!busy) { if (editing && text != baseline) action = "close" else if (editing) editing = false else onBack() } })
            Text("Files", color = LitterTheme.textPrimary, fontSize = 28.sp)
        }
        val guestPath = "/" + directory.relativeTo(files.root).path.trim('/')
        Text(guestPath, color = LitterTheme.textSecondary, fontSize = 18.sp)
        error?.let { Text(it, color = LitterTheme.danger) }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (editing) {
            Text(selected?.name.orEmpty(), color = LitterTheme.textPrimary)
            OutlinedTextField(text, { text = it }, modifier = Modifier.weight(1f).fillMaxWidth(), label = { Text("File contents") }, enabled = !busy)
            TvButton("Save", { selected?.let { path -> val content = text; perform(onSuccess = { baseline = content }) {
                check(files.read(path) == baseline) { "This file changed outside the editor. Reopen it before saving." }
                files.write(path, content)
            } } })
        } else {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TvButton("Refresh", { perform {} })
                TvButton("Up", { if (!busy && directory != files.root) { directory = files.checked(directory.parentFile!!); selected = null } })
                TvButton("New file", { if (!busy) { name = ""; action = "file" } })
                TvButton("New folder", { if (!busy) { name = ""; action = "folder" } })
                TvButton("Terminal here", { if (!busy) onTerminal(guestPath) })
                TvButton("Import", { if (!busy) try { importDirectory = directory; importer.launch("*/*") } catch (_: Exception) { error = "No file picker is installed on this TV." } })
            }
            selected?.let { item ->
                Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TvButton("Open", {
                        if (!busy) {
                            busy = true
                            scope.launch {
                                try {
                                    val path = withContext(Dispatchers.IO) { files.checked(item) }
                                    if (path.isDirectory) { directory = path; selected = null }
                                    else { text = withContext(Dispatchers.IO) { files.read(path) }; baseline = text; editing = true }
                                    error = null
                                } catch (e: CancellationException) { throw e }
                                catch (e: Exception) { error = e.message }
                                finally { busy = false }
                            }
                        }
                    })
                    TvButton("Rename", { if (!busy) { name = item.name; action = "rename" } })
                    TvButton("Move", { if (!busy) { name = guestPath; action = "move" } })
                    TvButton("Delete", { if (!busy) action = "delete" })
                    if (item.isFile) TvButton("Export", {
                        if (busy) return@TvButton
                        exportSource = item
                        try { exporter.launch(item.name) } catch (_: Exception) { exportSource = null; error = "No file export provider is installed on this TV." }
                    })
                }
            }
            LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(entries, key = { it.path }) { item ->
                    TvButton((if (item.isDirectory) "▸ " else "") + item.name, {
                        if (!busy) {
                            selected = item

                        }
                    }, Modifier.fillMaxWidth())
                }
            }
        }
    }
    BackHandler(enabled = editing || busy) { if (!busy) { if (text != baseline) action = "close" else editing = false } }
    action?.let { operation ->
        AlertDialog(onDismissRequest = { action = null }, title = { Text(when(operation) { "delete" -> "Delete ${selected?.name}?"; "close" -> "Close editor?"; "rename" -> "Rename"; "move" -> "Move to folder"; "folder" -> "New folder"; else -> "New file" }) },
            text = { if (operation == "delete") Text("Deletion is permanent, including the contents of folders.") else if (operation == "close") Text("Unsaved changes will be discarded.") else OutlinedTextField(name, { name = it }, label = { Text(if (operation == "move") "Destination folder, for example /root" else "Name") }, singleLine = true) },
            confirmButton = { TextButton(onClick = {
                action = null
                when (operation) {
                    "close" -> editing = false
                    "delete" -> selected?.let { path -> perform { files.delete(path) } }
                    "move" -> selected?.let { path -> val destination = name; perform { files.move(path, destination) } }
                    "rename" -> selected?.let { path -> val newName = name; perform { files.rename(path, newName) } }
                    else -> { val newName = name; val parent = directory; perform { files.create(parent, newName, operation == "folder") } }
                }
            }) { Text(if (operation == "delete") "Delete" else "Confirm") } },
            dismissButton = { TextButton(onClick = { action = null }) { Text("Cancel") } })
    }
}
