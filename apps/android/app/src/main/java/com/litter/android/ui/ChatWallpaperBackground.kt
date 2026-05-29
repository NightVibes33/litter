package com.litter.android.ui

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import uniffi.codex_mobile_client.ThreadKey

@Composable
fun ChatWallpaperBackground(
    threadKey: ThreadKey? = null,
    modifier: Modifier = Modifier,
) {
    WallpaperBackdrop(threadKey = threadKey, modifier = modifier.fillMaxSize())
}

@Composable
fun WallpaperBackdrop(
    threadKey: ThreadKey? = null,
    modifier: Modifier = Modifier,
) {
    // Read version to recompose when wallpaper prefs change
    @Suppress("UNUSED_VARIABLE")
    val ver = WallpaperManager.version
    val config = if (threadKey != null) WallpaperManager.resolvedConfig(threadKey) else null
    val bitmap = if (config != null) {
        WallpaperManager.resolvedBitmapForConfig(config, threadKey)
    } else {
        null
    }

    val isVideo = config?.type == WallpaperType.CUSTOM_VIDEO || config?.type == WallpaperType.VIDEO_URL
    val videoPath = if (isVideo) WallpaperManager.videoFilePath(threadKey) else null

    if (config != null && (bitmap != null || config.type == WallpaperType.SOLID_COLOR || (isVideo && videoPath != null))) {
        val blurRadius = wallpaperBlurRadius(config.blur)
        val brightnessAlpha = config.brightness.coerceIn(0f, 1f)
        val motion = rememberWallpaperMotionTransform(config.motionEnabled)

        if (isVideo && videoPath != null) {
            VideoWallpaperPlayer(
                filePath = videoPath,
                blurAmount = config.blur,
                brightnessAlpha = brightnessAlpha,
                motionTransform = motion,
                modifier = modifier.fillMaxSize(),
            )
        } else if (config.type == WallpaperType.SOLID_COLOR) {
            val color = config.colorHex?.let { colorFromHex(it) }
                ?: LitterTheme.background
            Box(
                modifier = modifier
                    .background(color)
                    .graphicsLayer { alpha = brightnessAlpha },
            )
        } else if (bitmap != null) {
            Image(
                bitmap = bitmap.asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = modifier
                    .blur(blurRadius)
                    .graphicsLayer {
                        alpha = brightnessAlpha
                        scaleX = motion.scale
                        scaleY = motion.scale
                        translationX = motion.translationX
                        translationY = motion.translationY
                    },
            )
        }
    } else {
        Box(
            modifier = modifier.background(LitterTheme.backgroundBrush),
        )
    }
}

data class WallpaperMotionTransform(
    val scale: Float,
    val translationX: Float,
    val translationY: Float,
)

@Composable
fun rememberWallpaperMotionTransform(enabled: Boolean): WallpaperMotionTransform {
    if (!enabled) {
        return WallpaperMotionTransform(scale = 1f, translationX = 0f, translationY = 0f)
    }

    val context = LocalContext.current
    val density = LocalDensity.current
    val maxTranslationX = with(density) { 26.dp.toPx() }
    val maxTranslationY = with(density) { 20.dp.toPx() }
    var targetTranslationX by remember { mutableFloatStateOf(0f) }
    var targetTranslationY by remember { mutableFloatStateOf(0f) }

    DisposableEffect(enabled, context, maxTranslationX, maxTranslationY) {
        if (!enabled) {
            targetTranslationX = 0f
            targetTranslationY = 0f
            return@DisposableEffect onDispose {}
        }

        val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        if (sensorManager == null) {
            return@DisposableEffect onDispose {}
        }

        val rotationSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        val gravitySensor = sensorManager.getDefaultSensor(Sensor.TYPE_GRAVITY)
        val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        val rotationMatrix = FloatArray(9)
        var gravityX = 0f
        var gravityY = 0f

        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                when (event.sensor.type) {
                    Sensor.TYPE_ROTATION_VECTOR -> {
                        SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values)
                        SensorManager.getOrientation(rotationMatrix, FloatArray(3)).also { orientation ->
                            val pitch = orientation[1]
                            val roll = orientation[2]
                            targetTranslationX =
                                ((-roll / 0.35f).coerceIn(-1f, 1f)) * maxTranslationX
                            targetTranslationY =
                                ((pitch / 0.35f).coerceIn(-1f, 1f)) * maxTranslationY
                        }
                    }

                    Sensor.TYPE_GRAVITY, Sensor.TYPE_ACCELEROMETER -> {
                        gravityX = (gravityX * 0.82f) + (event.values[0] * 0.18f)
                        gravityY = (gravityY * 0.82f) + (event.values[1] * 0.18f)
                        targetTranslationX =
                            ((gravityX / 5.5f).coerceIn(-1f, 1f)) * maxTranslationX
                        targetTranslationY =
                            ((gravityY / 5.5f).coerceIn(-1f, 1f)) * maxTranslationY
                    }
                }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        val sensor =
            rotationSensor ?: gravitySensor ?: accelerometer

        if (sensor != null) {
            sensorManager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_GAME)
        }

        onDispose {
            targetTranslationX = 0f
            targetTranslationY = 0f
            sensorManager.unregisterListener(listener)
        }
    }

    val translationX by animateFloatAsState(
        targetValue = targetTranslationX,
        animationSpec = tween(durationMillis = 120),
        label = "wallpaperMotionX",
    )
    val translationY by animateFloatAsState(
        targetValue = targetTranslationY,
        animationSpec = tween(durationMillis = 120),
        label = "wallpaperMotionY",
    )

    return WallpaperMotionTransform(
        scale = 1.12f,
        translationX = translationX,
        translationY = translationY,
    )
}

fun wallpaperBlurRadius(blurAmount: Float): Dp = (blurAmount.coerceIn(0f, 1f) * 40f).dp
