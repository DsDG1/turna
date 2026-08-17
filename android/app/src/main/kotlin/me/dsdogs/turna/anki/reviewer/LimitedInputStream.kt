package me.dsdogs.turna.anki.reviewer

import java.io.FilterInputStream
import java.io.InputStream

class LimitedInputStream(
    wrapped: InputStream,
    private var remaining: Long,
) : FilterInputStream(wrapped) {
    override fun read(): Int {
        if (remaining <= 0) return -1
        val value = super.read()
        if (value >= 0) remaining -= 1
        return value
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        if (remaining <= 0) return -1
        val toRead = minOf(len.toLong(), remaining).toInt()
        val n = super.read(b, off, toRead)
        if (n > 0) remaining -= n.toLong()
        return n
    }

    override fun skip(n: Long): Long {
        if (remaining <= 0 || n <= 0) return 0
        val skipped = super.skip(minOf(n, remaining))
        remaining -= skipped
        return skipped
    }

    override fun available(): Int {
        if (remaining <= 0) return 0
        return minOf(super.available().toLong(), remaining).toInt()
    }
}
