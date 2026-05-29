package com.litter.android.ui

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL

private const val TAG = "VideoWallpaperProcessor"
private const val MAX_DURATION_MS = 30_000L
private const val MAX_FILE_SIZE_BYTES = 50L * 1024 * 1024 // 50 MB

data class VideoProcessResult(
    val outputFile: File,
    val thumbnailFile: File,
    val durationSeconds: Float,
)

object VideoWallpaperProcessor {

    /**
     * Process a local video from a content URI.
     * Validates duration, copies to the wallpaper file location, and generates a thumbnail.
     */
    suspend fun processLocalVideo(
        context: Context,
        uri: Uri,
        scope: WallpaperScope,
    ): VideoProcessResult? = withContext(Dispatchers.IO) {
        val outputFile = WallpaperManager.videoFileForScope(scope) ?: return@withContext null
        val thumbnailFile = thumbnailFileForScope(context, scope) ?: return@withContext null

        // Validate duration
        val durationMs = getVideoDurationMs(context, uri)
        if (durationMs == null || durationMs > MAX_DURATION_MS) {
            Log.e(TAG, "Video too long or unreadable: ${durationMs}ms (max ${MAX_DURATION_MS}ms)")
            return@withContext null
        }

        // Copy video to app storage
        val copied = copyUriToFile(context, uri, outputFile)
        if (!copied) return@withContext null

        // Check file size
        if (outputFile.length() > MAX_FILE_SIZE_BYTES) {
            Log.e(TAG, "Video file too large: ${outputFile.length()} bytes")
            outputFile.delete()
            return@withContext null
        }

        // Generate thumbnail
        generateThumbnail(outputFile.absolutePath, thumbnailFile)

        VideoProcessResult(
            outputFile = outputFile,
            thumbnailFile = thumbnailFile,
            durationSeconds = durationMs / 1000f,
        )
    }

    /**
     * Download a remote video URL and process it.
     */
    suspend fun processRemoteUrl(
        context: Context,
        urlString: String,
        scope: WallpaperScope,
    ): VideoProcessResult? = withContext(Dispatchers.IO) {
        val outputFile = WallpaperManager.videoFileForScope(scope) ?: return@withContext null
        val thumbnailFile = thumbnailFileForScope(context, scope) ?: return@withContext null

        // Download to a temp file first
        val tempFile = File(context.cacheDir, "wallpaper_download_temp.mp4")
        val downloaded = downloadToFile(urlString, tempFile)
        if (!downloaded) {
            tempFile.delete()
            return@withContext null
        }

        // Validate duration
        val durationMs = getVideoDurationMs(tempFile.absolutePath)
        if (durationMs == null || durationMs > MAX_DURATION_MS) {
            Log.e(TAG, "Remote video too long or unreadable: ${durationMs}ms")
            tempFile.delete()
            return@withContext null
        }

        // Check file size
        if (tempFile.length() > MAX_FILE_SIZE_BYTES) {
            Log.e(TAG, "Remote video too large: ${tempFile.length()} bytes")
            tempFile.delete()
            return@withContext null
        }

        // Move temp to final location
        outputFile.parentFile?.mkdirs()
        tempFile.renameTo(outputFile)

        // Generate thumbnail
        generateThumbnail(outputFile.absolutePath, thumbnailFile)

        VideoProcessResult(
            outputFile = outputFile,
            thumbnailFile = thumbnailFile,
            durationSeconds = durationMs / 1000f,
        )
    }

    private fun getVideoDurationMs(context: Context, uri: Uri): Long? {
        return runCatching {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(context, uri)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            retriever.release()
            duration
        }.onFailure {
            Log.e(TAG, "Failed to get video duration", it)
        }.getOrNull()
    }

    private fun getVideoDurationMs(filePath: String): Long? {
        return runCatching {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(filePath)
            val duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            retriever.release()
            duration
        }.onFailure {
            Log.e(TAG, "Failed to get video duration from file", it)
        }.getOrNull()
    }

    private fun generateThumbnail(videoPath: String, thumbnailFile: File) {
        runCatching {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(videoPath)
            val frame = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            retriever.release()
            if (frame != null) {
                thumbnailFile.parentFile?.mkdirs()
                FileOutputStream(thumbnailFile).use { stream ->
                    frame.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                    stream.fd.sync()
                }
            }
        }.onFailure {
            Log.e(TAG, "Failed to generate thumbnail", it)
        }
    }

    private fun copyUriToFile(context: Context, uri: Uri, destFile: File): Boolean {
        return runCatching {
            destFile.parentFile?.mkdirs()
            context.contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                    output.fd.sync()
                }
            } ?: throw IllegalStateException("Could not open input stream for $uri")
        }.onFailure {
            Log.e(TAG, "Failed to copy URI to file", it)
        }.isSuccess
    }

    private fun downloadToFile(urlString: String, destFile: File): Boolean {
        return runCatching {
            destFile.parentFile?.mkdirs()
            val url = URL(urlString)
            val connection = url.openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.connect()
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                throw IllegalStateException("HTTP ${connection.responseCode}")
            }
            connection.inputStream.use { input ->
                FileOutputStream(destFile).use { output ->
                    input.copyTo(output)
                    output.fd.sync()
                }
            }
            connection.disconnect()
        }.onFailure {
            Log.e(TAG, "Failed to download video from $urlString", it)
        }.isSuccess
    }

    private fun thumbnailFileForScope(context: Context, scope: WallpaperScope): File? {
        val fileKey = when (scope) {
            is WallpaperScope.Thread -> "${scope.key.serverId}_${scope.key.threadId}"
            is WallpaperScope.Server -> "server_${scope.serverId}"
            WallpaperScope.Pending -> "pending"
        }
        return File(context.filesDir, "wallpaper_${fileKey}_thumb.jpg")
    }
}
