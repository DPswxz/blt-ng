package com.kkkunny.blt

import android.media.MediaCodecList
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory("blt/media3", TclPlayerFactory(flutterEngine.dartExecutor.binaryMessenger))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "blt/playback").setMethodCallHandler { call, result ->
            if (call.method != "supports") { result.notImplemented(); return@setMethodCallHandler }
            val mime = when (call.argument<Int>("codec")) { 7 -> "video/avc"; 12 -> "video/hevc"; 13 -> "video/av01"; else -> "" }
            val width = call.argument<Int>("width") ?: 0
            val height = call.argument<Int>("height") ?: 0
            val fps = call.argument<Double>("fps") ?: 0.0
            val supported = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { codec ->
                val hardware = if (Build.VERSION.SDK_INT >= 29) codec.isHardwareAccelerated else
                    !codec.name.startsWith("OMX.google.") && !codec.name.startsWith("c2.android.")
                if (codec.isEncoder || !hardware || !codec.supportedTypes.any { it.equals(mime, true) }) false
                else try {
                    val video = codec.getCapabilitiesForType(mime).videoCapabilities ?: return@any false
                    if (width <= 0 || height <= 0) true
                    else if (fps > 0) video.areSizeAndRateSupported(width, height, fps)
                    else video.isSizeSupported(width, height)
                } catch (_: Exception) { false }
            }
            result.success(supported)
        }
    }
}
