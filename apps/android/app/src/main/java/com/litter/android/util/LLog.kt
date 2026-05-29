package com.litter.android.util

import android.content.Context
import android.util.Log
import com.litter.android.core.bridge.UniffiInit
import org.json.JSONObject

object LLog {
    @Volatile private var bootstrapped = false

    fun bootstrap(context: Context) {
        if (bootstrapped) return
        synchronized(this) {
            if (bootstrapped) return
            UniffiInit.ensure(context)
            bootstrapped = true
        }
    }

    fun t(tag: String, message: String, fields: Map<String, Any?> = emptyMap(), payloadJson: String? = null) {
        Log.v(tag, render(message, fields, payloadJson))
    }

    fun d(tag: String, message: String, fields: Map<String, Any?> = emptyMap(), payloadJson: String? = null) {
        Log.d(tag, render(message, fields, payloadJson))
    }

    fun i(tag: String, message: String, fields: Map<String, Any?> = emptyMap(), payloadJson: String? = null) {
        Log.i(tag, render(message, fields, payloadJson))
    }

    fun w(tag: String, message: String, fields: Map<String, Any?> = emptyMap(), payloadJson: String? = null) {
        Log.w(tag, render(message, fields, payloadJson))
    }

    fun e(
        tag: String,
        message: String,
        throwable: Throwable? = null,
        fields: Map<String, Any?> = emptyMap(),
        payloadJson: String? = null,
    ) {
        val mergedFields = fields.toMutableMap()
        if (throwable != null) {
            mergedFields["error"] = throwable.message ?: throwable.javaClass.simpleName
        }

        val rendered = render(message, mergedFields, payloadJson)
        if (throwable != null) {
            Log.e(tag, rendered, throwable)
        } else {
            Log.e(tag, rendered)
        }
    }

    private fun render(message: String, fields: Map<String, Any?>, payloadJson: String?): String {
        val parts = mutableListOf(message)
        fieldsJson(fields)?.let { parts += "fields=$it" }
        payloadJson?.takeIf { it.isNotBlank() }?.let { parts += "payload=$it" }
        return parts.joinToString(separator = " ")
    }

    private fun fieldsJson(fields: Map<String, Any?>): String? {
        if (fields.isEmpty()) return null
        val filtered = fields.filterValues { it != null }
        if (filtered.isEmpty()) return null
        return JSONObject(filtered).toString()
    }
}
