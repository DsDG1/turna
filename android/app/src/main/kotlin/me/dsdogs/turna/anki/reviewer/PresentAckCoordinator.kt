package me.dsdogs.turna.anki.reviewer

/**
 * One active present at a time. A newer request completes the previous
 * Flutter result with RENDER_SUPERSEDED. Each poll must capture its own
 * request id so a stale completion cannot overwrite a newer page height.
 */
class PresentAckCoordinator {
    data class Request(
        val id: Long,
        val generation: Long,
        val side: String,
    )

    data class PresentResult(
        val ok: Boolean,
        val code: String? = null,
        val generation: Long? = null,
        val side: String? = null,
        val height: Double? = null,
        val recoverable: Boolean = false,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "ok" to ok,
            "code" to (code ?: ""),
            "generation" to generation,
            "side" to (side ?: ""),
            "height" to (height ?: 0.0),
            "recoverable" to recoverable,
        )
    }

    private var nextId = 0L
    private var active: Request? = null
    private var lastHeightGeneration = 0L
    var lastHeight: Double = 0.0
        private set

    fun begin(
        generation: Long,
        side: String,
        completeOld: (PresentResult) -> Unit,
    ): Request {
        val previous = active
        if (previous != null) {
            completeOld(
                PresentResult(
                    ok = false,
                    code = CODE_SUPERSEDED,
                    generation = previous.generation,
                    side = previous.side,
                    recoverable = true,
                ),
            )
        }
        val request = Request(id = ++nextId, generation = generation, side = side)
        active = request
        return request
    }

    fun isActive(requestId: Long): Boolean = active?.id == requestId

    fun activeRequest(): Request? = active

    fun shouldPublishHeight(generation: Long, height: Double): Boolean {
        val activeGeneration = active?.generation ?: lastHeightGeneration
        if (generation < lastHeightGeneration || generation < activeGeneration) {
            return false
        }
        lastHeightGeneration = generation
        lastHeight = height
        return true
    }

    fun complete(requestId: Long, result: PresentResult): PresentResult? {
        val current = active ?: return null
        if (current.id != requestId) return null
        active = null
        val gen = result.generation ?: current.generation
        if (result.ok && result.height != null) {
            if (!shouldPublishHeight(gen, result.height)) {
                return result.copy(height = lastHeight)
            }
        }
        return result
    }

    fun cancel(requestId: Long, result: PresentResult): PresentResult? {
        if (!isActive(requestId)) return null
        active = null
        return result
    }

    companion object {
        const val CODE_SUPERSEDED = "RENDER_SUPERSEDED"
    }
}
