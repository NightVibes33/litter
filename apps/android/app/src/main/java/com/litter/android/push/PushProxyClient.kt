package com.litter.android.push

import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class PushProxyClient {
    companion object {
        const val BASE_URL = "https://push.sigkitten.com"
    }

    fun register(
        platform: String,
        pushToken: String,
        contentState: Map<String, Any>,
        startTimestamp: Long,
        intervalSeconds: Int = 30,
        ttlSeconds: Int = 7200,
    ): String {
        val body = JSONObject().apply {
            put("platform", platform)
            put("pushToken", pushToken)
            put("contentState", JSONObject(contentState))
            put("startTimestamp", startTimestamp)
            put("intervalSeconds", intervalSeconds)
            put("ttlSeconds", ttlSeconds)
        }
        val response = post("/register", body)
        return response.getString("id")
    }

    fun update(registrationId: String, contentState: Map<String, Any>) {
        val body = JSONObject().apply {
            put("contentState", JSONObject(contentState))
        }
        post("/$registrationId/update", body)
    }

    fun end(registrationId: String) {
        post("/$registrationId/end", JSONObject())
    }

    fun deregister(registrationId: String) {
        post("/$registrationId/deregister", JSONObject())
    }

    private fun post(path: String, body: JSONObject): JSONObject {
        val connection = (URL("$BASE_URL$path").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            doOutput = true
        }
        connection.outputStream.use { out ->
            OutputStreamWriter(out, Charsets.UTF_8).use { it.write(body.toString()) }
        }
        val responseBody = if (connection.responseCode in 200..299) {
            connection.inputStream.bufferedReader().use { it.readText() }
        } else {
            val error = connection.errorStream?.bufferedReader()?.use { it.readText() } ?: ""
            throw RuntimeException("Push proxy $path failed (${connection.responseCode}): $error")
        }
        return if (responseBody.isBlank()) JSONObject() else JSONObject(responseBody)
    }
}
