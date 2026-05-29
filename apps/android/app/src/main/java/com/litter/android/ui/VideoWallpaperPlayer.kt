package com.litter.android.ui

import android.graphics.RenderEffect
import android.graphics.Shader
import android.os.Build
import android.view.ViewGroup
import android.net.Uri
import android.view.TextureView
import androidx.annotation.OptIn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import java.io.File

@OptIn(UnstableApi::class)
@Composable
fun VideoWallpaperPlayer(
    filePath: String,
    blurAmount: Float = 0f,
    brightnessAlpha: Float = 1f,
    motionTransform: WallpaperMotionTransform = WallpaperMotionTransform(
        scale = 1f,
        translationX = 0f,
        translationY = 0f,
    ),
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    val player = remember(filePath) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(Uri.fromFile(File(filePath))))
            repeatMode = Player.REPEAT_MODE_ONE
            volume = 0f
            prepare()
            play()
        }
    }

    DisposableEffect(lifecycleOwner, player) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_PAUSE -> player.pause()
                Lifecycle.Event.ON_RESUME -> player.play()
                else -> {}
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
            player.clearVideoTextureView(null)
            player.release()
        }
    }

    AndroidView(
        factory = { ctx ->
            TextureView(ctx).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                )
                player.setVideoTextureView(this)
            }
        },
        update = { view ->
            player.setVideoTextureView(view)
            view.alpha = brightnessAlpha.coerceIn(0f, 1f)
            view.scaleX = motionTransform.scale
            view.scaleY = motionTransform.scale
            view.translationX = motionTransform.translationX
            view.translationY = motionTransform.translationY

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val blurRadiusPx = blurAmount.coerceIn(0f, 1f) * 48f
                view.setRenderEffect(
                    if (blurRadiusPx > 0f) {
                        RenderEffect.createBlurEffect(
                            blurRadiusPx,
                            blurRadiusPx,
                            Shader.TileMode.CLAMP,
                        )
                    } else {
                        null
                    },
                )
            }
        },
        modifier = modifier,
    )
}
