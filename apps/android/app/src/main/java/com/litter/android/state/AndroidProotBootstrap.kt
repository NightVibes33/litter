package com.litter.android.state

import android.content.Context
import android.util.Log
import java.io.File
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import uniffi.codex_mobile_client.prootBootstrap
import uniffi.codex_mobile_client.ProotBootstrapException

object AndroidProotBootstrap {
    private const val TAG = "AndroidProotBootstrap"
    private const val ROOTFS_ASSET = "alpine-fs.tgz"
    private const val ROOTFS_VERSION_ASSET = "alpine-fs.version"

    enum class Status {
        Pending,
        Bootstrapping,
        Ready,
        MissingArtifact,
        PtraceDenied,
        Failed,
    }

    data class BootstrapState(
        val status: Status = Status.Pending,
        val message: String? = null,
    )

    private val _state = MutableStateFlow(BootstrapState())
    val state: StateFlow<BootstrapState> = _state

    fun bootstrap(context: Context) {
        val appContext = context.applicationContext
        _state.value = BootstrapState(Status.Bootstrapping)
        val archive = File(appContext.filesDir, ROOTFS_ASSET)
        if (!copyRootfsAssets(appContext, archive)) {
            Log.w(TAG, "Skipping proot bootstrap; $ROOTFS_ASSET is not bundled")
            _state.value = BootstrapState(
                status = Status.MissingArtifact,
                message = "$ROOTFS_ASSET is not bundled",
            )
            return
        }

        try {
            val dataDir = File(appContext.filesDir, "proot")
            dataDir.mkdirs()
            prootBootstrap(
                appContext.applicationInfo.nativeLibraryDir,
                archive.absolutePath,
                dataDir.absolutePath,
            )
            _state.value = BootstrapState(Status.Ready)
            Log.i(TAG, "Android proot bootstrap complete")
        } catch (error: ProotBootstrapException.PtraceDenied) {
            Log.w(TAG, "Android proot ptrace denied", error)
            _state.value = BootstrapState(
                status = Status.PtraceDenied,
                message = error.detail,
            )
        } catch (error: ProotBootstrapException.MissingArtifact) {
            Log.w(TAG, "Android proot artifact missing", error)
            _state.value = BootstrapState(
                status = Status.MissingArtifact,
                message = error.detail,
            )
        } catch (error: Throwable) {
            Log.w(TAG, "Android proot bootstrap failed", error)
            _state.value = BootstrapState(
                status = Status.Failed,
                message = error.message ?: "Android proot bootstrap failed",
            )
        }
    }

    private fun copyRootfsAssets(context: Context, dest: File): Boolean {
        return try {
            val bundledVersion = readAssetBytes(context, ROOTFS_VERSION_ASSET)
            val versionDest = File(dest.parentFile, ROOTFS_VERSION_ASSET)
            val installedVersion = versionDest.takeIf { it.isFile }?.readBytes()
            val versionChanged = bundledVersion != null &&
                (installedVersion == null || !installedVersion.contentEquals(bundledVersion))
            if (dest.isFile && dest.length() > 0L && !versionChanged) {
                return true
            }

            copyAssetAtomically(context, ROOTFS_ASSET, dest)
            if (bundledVersion != null) {
                writeBytesAtomically(versionDest, bundledVersion)
            } else {
                versionDest.delete()
            }
            true
        } catch (error: java.io.FileNotFoundException) {
            false
        } catch (error: Throwable) {
            Log.w(TAG, "Unable to copy Android proot rootfs assets", error)
            false
        }
    }

    private fun readAssetBytes(context: Context, asset: String): ByteArray? =
        try {
            context.assets.open(asset).use { it.readBytes() }
        } catch (_: java.io.FileNotFoundException) {
            null
        }

    private fun copyAssetAtomically(context: Context, asset: String, dest: File) {
        context.assets.open(asset).use { input ->
            dest.parentFile?.mkdirs()
            val tmp = File(dest.parentFile, "${dest.name}.tmp")
            tmp.outputStream().use { output -> input.copyTo(output) }
            if (!tmp.renameTo(dest)) {
                tmp.copyTo(dest, overwrite = true)
                tmp.delete()
            }
        }
    }

    private fun writeBytesAtomically(dest: File, bytes: ByteArray) {
        dest.parentFile?.mkdirs()
        val tmp = File(dest.parentFile, "${dest.name}.tmp")
        tmp.writeBytes(bytes)
        if (!tmp.renameTo(dest)) {
            tmp.copyTo(dest, overwrite = true)
            tmp.delete()
        }
    }
}
