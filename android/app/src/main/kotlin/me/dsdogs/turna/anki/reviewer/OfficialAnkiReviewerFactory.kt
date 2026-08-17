package me.dsdogs.turna.anki.reviewer

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class OfficialAnkiReviewerFactory(
    private val messenger: BinaryMessenger,
    private val assetLoader: (String) -> ByteArray?,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<*, *>
        return OfficialAnkiReviewerPlatformView(
            context,
            messenger,
            viewId,
            params,
            assetLoader,
        )
    }
}
