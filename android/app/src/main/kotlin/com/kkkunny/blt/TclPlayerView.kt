package com.kkkunny.blt

import android.content.Context
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import android.view.View
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.ui.AspectRatioFrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class TclPlayerFactory(private val messenger: BinaryMessenger) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = TclPlayerView(context, viewId, messenger)
}

@UnstableApi
class TclPlayerView(context: Context, id: Int, messenger: BinaryMessenger) : PlatformView {
    private val frame = AspectRatioFrameLayout(context)
    private val surface = SurfaceView(context)
    private val handler = Handler(Looper.getMainLooper())
    private val methods = MethodChannel(messenger, "blt/media3/$id")
    private val events = EventChannel(messenger, "blt/media3/$id/events")
    private var sink: EventChannel.EventSink? = null
    private var eventsCancelled = false
    private var released = false
    private var decoder = "initializing"
    private var dropped = 0
    private var rendered = 0
    private val player = ExoPlayer.Builder(context)
        .setRenderersFactory(DefaultRenderersFactory(context).setEnableDecoderFallback(true))
        .setLoadControl(DefaultLoadControl.Builder()
            .setBufferDurationsMs(15000, 45000, 1000, 2000)
            .setTargetBufferBytes(32 * 1024 * 1024)
            .setPrioritizeTimeOverSizeThresholds(false).build())
        .build()
    private val ticker = object : Runnable {
        override fun run() {
            if (released) return
            emit()
            handler.postDelayed(this, 500)
        }
    }
    init {
        frame.setBackgroundColor(Color.BLACK)
        frame.isFocusable = false
        surface.isFocusable = false
        surface.keepScreenOn = true
        frame.addView(surface, android.widget.FrameLayout.LayoutParams(-1, -1, android.view.Gravity.CENTER))
        player.setVideoSurfaceView(surface)
        player.setVideoScalingMode(C.VIDEO_SCALING_MODE_SCALE_TO_FIT)
        player.addListener(object : Player.Listener {
            override fun onVideoSizeChanged(size: androidx.media3.common.VideoSize) {
                if (size.height > 0) frame.setAspectRatio(size.width * size.pixelWidthHeightRatio / size.height)
            }
            override fun onPlaybackStateChanged(state: Int) { emit() }
            override fun onIsPlayingChanged(isPlaying: Boolean) { emit() }
            override fun onPlayerError(error: PlaybackException) {
                // Do not forward URLs, request headers or tokens to Flutter logs.
                sink?.success(mapOf("error" to "ExoPlayer ${error.errorCodeName}"))
            }
        })
        player.addAnalyticsListener(object : AnalyticsListener {
            override fun onVideoDecoderInitialized(time: AnalyticsListener.EventTime, name: String, initializedTimestampMs: Long, initializationDurationMs: Long) {
                decoder = name
                sink?.success(mapOf("log" to "ExoPlayer decoder=$name"))
            }
            override fun onDroppedVideoFrames(time: AnalyticsListener.EventTime, count: Int, elapsedMs: Long) { dropped += count }
            override fun onRenderedFirstFrame(time: AnalyticsListener.EventTime, output: Any, renderTimeMs: Long) {
                rendered++
                sink?.success(mapOf("log" to "ExoPlayer firstFrame decoder=$decoder"))
            }
        })
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
                eventsCancelled = false
                sink = eventSink
                emit()
            }
            override fun onCancel(arguments: Any?) {
                eventsCancelled = true
                sink = null
                if (released) events.setStreamHandler(null)
            }
        })
        methods.setMethodCallHandler { call, result ->
            if (released && call.method != "release") { result.error("released", "播放器已关闭", null); return@setMethodCallHandler }
            try {
                when (call.method) {
                    "open" -> {
                        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                        val http = DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(true)
                            .setConnectTimeoutMs(12000).setReadTimeoutMs(20000).setDefaultRequestProperties(headers)
                        fun source(url: String): MediaSource = ProgressiveMediaSource.Factory(http).createMediaSource(MediaItem.fromUri(url))
                        val video = source(call.argument<String>("video")!!)
                        val audio = call.argument<String>("audio")
                        val media = if (audio.isNullOrEmpty()) video else MergingMediaSource(true, true, video, source(audio))
                        // Finish the old codec before replacing its stream. On T982,
                        // reusing live video buffers across formats can exercise the
                        // vendor UVM/GPU reallocation path seen in kernel panics.
                        player.pause()
                        player.stop()
                        dropped = 0; rendered = 0; decoder = "initializing"
                        player.setMediaSource(media, (call.argument<Number>("start")?.toLong() ?: 0L).coerceAtLeast(0))
                        player.prepare()
                        player.playWhenReady = true
                    }
                    "seek" -> player.seekTo((call.argument<Number>("position")?.toLong() ?: 0).coerceAtLeast(0))
                    "playing" -> player.playWhenReady = call.argument<Boolean>("value") ?: true
                    "rate" -> player.setPlaybackSpeed((call.argument<Number>("value")?.toFloat() ?: 1f))
                    "loop" -> player.repeatMode = if (call.argument<Boolean>("value") == true) Player.REPEAT_MODE_ONE else Player.REPEAT_MODE_OFF
                    "aspect" -> frame.resizeMode = when (call.argument<String>("value")) {
                        "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                        "cover" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                        else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                    }
                    "metrics" -> emit(true)
                    "release" -> releasePlayer()
                    else -> { result.notImplemented(); return@setMethodCallHandler }
                }
                result.success(null)
            } catch (error: Exception) { result.error("player", error.javaClass.simpleName, null) }
        }
        handler.post(ticker)
    }
    private fun emit(metrics: Boolean = false) {
        if (released) return
        val duration = if (player.duration == C.TIME_UNSET) 0L else player.duration.coerceAtLeast(0)
        val data = mutableMapOf<String, Any>(
            "position" to player.currentPosition.coerceAtLeast(0), "duration" to duration,
            "buffer" to player.bufferedPosition.coerceAtLeast(0),
            "playing" to player.playWhenReady, "buffering" to (player.playbackState == Player.STATE_BUFFERING),
            "completed" to (player.playbackState == Player.STATE_ENDED))
        if (metrics) {
            val counters = player.videoDecoderCounters
            counters?.ensureUpdated()
            data["log"] = "ExoPlayer decoder=$decoder size=${player.videoFormat?.width}x${player.videoFormat?.height} position=${player.currentPosition} buffered=${player.bufferedPosition} dropped=$dropped rendered=${counters?.renderedOutputBufferCount ?: 0} firstFrames=$rendered playing=${player.isPlaying}"
        }
        sink?.success(data)
    }
    private fun releasePlayer() {
        if (released) return
        released = true
        handler.removeCallbacks(ticker)
        // Stop releases the decoder while its real SurfaceView still exists.
        // Clearing a live codec's surface first can make Media3 switch it to a
        // dummy GPU surface, needlessly importing video DMA buffers into Mali.
        player.pause()
        player.stop()
        player.clearMediaItems()
        player.clearVideoSurfaceView(surface)
        player.release()
        if (eventsCancelled) events.setStreamHandler(null)
    }
    override fun getView(): View = frame
    override fun dispose() {
        releasePlayer()
        sink = null
        methods.setMethodCallHandler(null)
        // Dart may cancel its subscription after the platform view is gone.
        // Keep only this no-op cancel endpoint until that handshake finishes.
        // onCancel then unregisters it, without retaining a codec or Surface.
    }
    override fun onFlutterViewDetached() { if (!released) player.pause() }
}
