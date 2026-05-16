package com.litter.android.state

import android.content.Context
import android.net.Uri
import android.util.Base64
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.litter.android.util.LLog
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.BufferedReader
import java.io.IOException
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.UnknownHostException
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom

data class ChatGPTOAuthTokenBundle(
    val accessToken: String,
    val idToken: String,
    val refreshToken: String?,
    val accountId: String,
    val planType: String?,
)

class ChatGPTOAuthException(message: String) : Exception(message)

object ChatGPTOAuth {
    const val MODE_LOGIN = "login"
    const val MODE_REMOTE_CONTROL_ENROLL = "remote_control_enroll"
    const val authIssuer = "https://auth.openai.com"
    private const val clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    private const val callbackScheme = "http"
    private const val callbackHost = "localhost"
    private const val callbackBindHost = "127.0.0.1"
    private const val callbackPort = 1455
    private const val callbackPath = "/auth/callback"
    private const val tokenExchangeMaxAttempts = 5

    data class AuthAttempt(
        val state: String,
        val codeVerifier: String,
        val redirectUri: String,
        val authorizeUrl: String,
        val mode: String = MODE_LOGIN,
    )

    fun createLoginAttempt(): AuthAttempt {
        val state = java.util.UUID.randomUUID().toString()
        val codeVerifier = generatePkceCodeVerifier()
        val codeChallenge = generatePkceCodeChallenge(codeVerifier)
        val redirectUri = "$callbackScheme://$callbackHost:$callbackPort$callbackPath"
        val authorizeUrl = Uri.parse("$authIssuer/oauth/authorize")
            .buildUpon()
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("client_id", clientId)
            .appendQueryParameter("redirect_uri", redirectUri)
            .appendQueryParameter("scope", "openid profile email offline_access")
            .appendQueryParameter("code_challenge", codeChallenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .appendQueryParameter("state", state)
            .appendQueryParameter("id_token_add_organizations", "true")
            .appendQueryParameter("codex_cli_simplified_flow", "true")
            .build()
            .toString()
        return AuthAttempt(
            state = state,
            codeVerifier = codeVerifier,
            redirectUri = redirectUri,
            authorizeUrl = authorizeUrl,
            mode = MODE_LOGIN,
        )
    }

    fun createRemoteControlEnrollmentAttempt(): AuthAttempt {
        val state = java.util.UUID.randomUUID().toString()
        val codeVerifier = generatePkceCodeVerifier()
        val codeChallenge = generatePkceCodeChallenge(codeVerifier)
        val redirectUri = "$callbackScheme://$callbackHost:$callbackPort$callbackPath"
        val authorizeUrl = Uri.parse("$authIssuer/oauth/authorize")
            .buildUpon()
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("client_id", clientId)
            .appendQueryParameter("redirect_uri", redirectUri)
            .appendQueryParameter("scope", "codex.remote_control.enroll")
            .appendQueryParameter("code_challenge", codeChallenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .appendQueryParameter("state", state)
            .appendQueryParameter("originator", "Codex Desktop")
            .appendQueryParameter("reauth", "remote_control")
            .appendQueryParameter("max_age", "0")
            .appendQueryParameter("codex_cli_simplified_flow", "true")
            .build()
            .toString()
        LLog.i(
            "Slingshot",
            "remote-control step-up auth attempt created",
            fields = mapOf("state" to state, "redirectUri" to redirectUri),
        )
        return AuthAttempt(
            state = state,
            codeVerifier = codeVerifier,
            redirectUri = redirectUri,
            authorizeUrl = authorizeUrl,
            mode = MODE_REMOTE_CONTROL_ENROLL,
        )
    }

    fun isRemoteControlAuthorizationRequired(error: Throwable): Boolean {
        val message = "${error.message.orEmpty()} ${error}".lowercase()
        return message.contains("missing slingshot remote-control authorization token") ||
            message.contains("missing slingshot client session token") ||
            message.contains("remote-control authorization")
    }

    suspend fun loadStoredOrRefreshedTokens(context: Context): ChatGPTOAuthTokenBundle? {
        val appContext = context.applicationContext
        val stored = ChatGPTOAuthTokenStore(appContext).load() ?: return null
        return runCatching {
            refreshStoredTokens(appContext, stored.accountId)
        }.getOrElse {
            stored
        }
    }

    suspend fun requireStoredOrRefreshedTokens(
        context: Context,
        missingMessage: String,
    ): ChatGPTOAuthTokenBundle =
        loadStoredOrRefreshedTokens(context) ?: throw IllegalStateException(missingMessage)

    fun isCallbackUri(uri: Uri): Boolean {
        val host = uri.host?.lowercase()
        return uri.scheme == callbackScheme &&
            (host == callbackHost || host == callbackBindHost) &&
            uri.path == callbackPath
    }

    suspend fun completeAuthorization(
        context: Context,
        callbackUri: Uri,
        attempt: AuthAttempt,
    ): ChatGPTOAuthTokenBundle {
        validateCallbackUri(callbackUri)
        val error = callbackUri.getQueryParameter("error")?.trim()
        if (!error.isNullOrEmpty()) {
            val description = callbackUri.getQueryParameter("error_description")?.trim()
            throw ChatGPTOAuthException(
                description?.takeIf { it.isNotEmpty() } ?: error,
            )
        }

        val state = callbackUri.getQueryParameter("state")
        if (state != attempt.state) {
            throw ChatGPTOAuthException("ChatGPT login state did not match the original request.")
        }

        val code = callbackUri.getQueryParameter("code")?.trim()
        if (code.isNullOrEmpty()) {
            throw ChatGPTOAuthException("ChatGPT login did not return an authorization code.")
        }

        val body = listOf(
            "grant_type=authorization_code",
            "code=${Uri.encode(code)}",
            "redirect_uri=${Uri.encode(attempt.redirectUri)}",
            "client_id=${Uri.encode(clientId)}",
            "code_verifier=${Uri.encode(attempt.codeVerifier)}",
        ).joinToString("&")

        val tokens = exchangeToken(body)
        ChatGPTOAuthTokenStore(context).save(tokens)
        return tokens
    }

    suspend fun completeRemoteControlEnrollmentAuthorization(
        callbackUri: Uri,
        attempt: AuthAttempt,
    ): String {
        validateAuthorizationCallback(callbackUri, attempt)
        LLog.i(
            "Slingshot",
            "remote-control step-up auth callback received",
            fields = mapOf("state" to attempt.state),
        )
        val code = callbackUri.getQueryParameter("code")?.trim()
            ?: throw ChatGPTOAuthException("ChatGPT login did not return an authorization code.")
        if (code.isEmpty()) {
            throw ChatGPTOAuthException("ChatGPT login did not return an authorization code.")
        }

        val body = listOf(
            "grant_type=authorization_code",
            "code=${Uri.encode(code)}",
            "redirect_uri=${Uri.encode(attempt.redirectUri)}",
            "client_id=${Uri.encode(clientId)}",
            "code_verifier=${Uri.encode(attempt.codeVerifier)}",
        ).joinToString("&")

        val token = exchangeAccessToken(body)
        LLog.i(
            "Slingshot",
            "remote-control step-up token received",
            fields = mapOf("tokenLength" to token.length),
        )
        return token
    }

    suspend fun refreshStoredTokens(
        context: Context,
        previousAccountId: String?,
    ): ChatGPTOAuthTokenBundle {
        val stored = ChatGPTOAuthTokenStore(context).load()
            ?: throw ChatGPTOAuthException("No stored ChatGPT login is available to refresh.")
        val refreshToken = stored.refreshToken?.takeIf { it.isNotBlank() }
            ?: throw ChatGPTOAuthException("No ChatGPT refresh token is available.")
        val body = listOf(
            "grant_type=refresh_token",
            "refresh_token=${Uri.encode(refreshToken)}",
            "client_id=${Uri.encode(clientId)}",
        ).joinToString("&")
        val refreshed = exchangeToken(body)
        if (!previousAccountId.isNullOrBlank() &&
            refreshed.accountId != previousAccountId &&
            stored.accountId != previousAccountId
        ) {
            throw ChatGPTOAuthException("ChatGPT refresh returned a different account than expected.")
        }
        ChatGPTOAuthTokenStore(context).save(refreshed)
        return refreshed
    }

    private suspend fun exchangeToken(body: String): ChatGPTOAuthTokenBundle = withContext(Dispatchers.IO) {
        tokenBundleFromPayload(exchangeTokenPayloadWithRetries(body))
    }

    private suspend fun exchangeAccessToken(body: String): String = withContext(Dispatchers.IO) {
        val payload = exchangeTokenPayloadWithRetries(body)
        val accessToken = payload.optString("access_token").trim()
        if (accessToken.isEmpty()) {
            throw ChatGPTOAuthException("ChatGPT token exchange failed: missing access_token.")
        }
        accessToken
    }

    private fun tokenBundleFromPayload(payload: JSONObject): ChatGPTOAuthTokenBundle {
        val accessToken = payload.optString("access_token").trim()
        val idToken = payload.optString("id_token").trim()
        val refreshToken = payload.optString("refresh_token").trim().ifEmpty { null }
        if (accessToken.isEmpty() || idToken.isEmpty()) {
            throw ChatGPTOAuthException("ChatGPT token exchange failed: missing access_token or id_token.")
        }

        val idClaims = decodeJwtClaims(idToken)
        val accessClaims = decodeJwtClaims(accessToken)
        val accountId = resolveAccountId(idClaims, accessClaims)
        if (accountId.isEmpty()) {
            throw ChatGPTOAuthException("ChatGPT login did not include an account identifier.")
        }

        return ChatGPTOAuthTokenBundle(
            accessToken = accessToken,
            idToken = idToken,
            refreshToken = refreshToken,
            accountId = accountId,
            planType = resolvePlanType(idClaims, accessClaims),
        )
    }

    private suspend fun exchangeTokenPayloadWithRetries(body: String): JSONObject {
        var networkFailure: IOException? = null
        repeat(tokenExchangeMaxAttempts) { attemptIndex ->
            try {
                return exchangeTokenPayload(body)
            } catch (error: UnknownHostException) {
                networkFailure = error
                if (attemptIndex == tokenExchangeMaxAttempts - 1) {
                    throw ChatGPTOAuthException(
                        "ChatGPT token exchange could not reach auth.openai.com. Check the device connection and try again.",
                    )
                }
                logTokenExchangeRetry(error, attemptIndex)
                delay(tokenExchangeRetryDelayMs(attemptIndex))
            } catch (error: IOException) {
                networkFailure = error
                if (attemptIndex == tokenExchangeMaxAttempts - 1) {
                    throw ChatGPTOAuthException(
                        "ChatGPT token exchange failed: ${error.localizedMessage ?: error.message ?: error.javaClass.simpleName}",
                    )
                }
                logTokenExchangeRetry(error, attemptIndex)
                delay(tokenExchangeRetryDelayMs(attemptIndex))
            }
        }
        throw networkFailure ?: ChatGPTOAuthException("ChatGPT token exchange failed before it could start.")
    }

    private fun tokenExchangeRetryDelayMs(attemptIndex: Int): Long =
        when (attemptIndex) {
            0 -> 500L
            1 -> 1_000L
            2 -> 2_000L
            else -> 4_000L
        }

    private fun logTokenExchangeRetry(error: IOException, attemptIndex: Int) {
        LLog.w(
            "ChatGPTOAuth",
            "ChatGPT token exchange network failure; retrying",
            fields = mapOf(
                "attempt" to (attemptIndex + 1),
                "maxAttempts" to tokenExchangeMaxAttempts,
                "errorType" to error.javaClass.simpleName,
                "message" to (error.localizedMessage ?: error.message).orEmpty().take(160),
                "nextDelayMs" to tokenExchangeRetryDelayMs(attemptIndex),
            ),
        )
    }

    private fun exchangeTokenPayload(body: String): JSONObject {
        val url = URL("$authIssuer/oauth/token")
        val connection = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 20_000
            readTimeout = 20_000
            doOutput = true
            setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
        }

        try {
            LLog.i(
                "ChatGPTOAuth",
                "ChatGPT token exchange request",
                fields = mapOf(
                    "url" to url.toString(),
                    "grantType" to formValue(body, "grant_type"),
                ),
            )
            connection.outputStream.use { output ->
                output.write(body.toByteArray(Charsets.UTF_8))
            }

            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val responseText = stream?.use { input ->
                BufferedReader(InputStreamReader(input)).readText()
            }.orEmpty()

            LLog.i(
                "ChatGPTOAuth",
                "ChatGPT token exchange response",
                fields = mapOf(
                    "status" to status,
                    "keys" to jsonObjectKeys(responseText).joinToString(","),
                ),
            )
            if (status !in 200..299) {
                LLog.w(
                    "ChatGPTOAuth",
                    "ChatGPT token exchange failed",
                    fields = mapOf("status" to status, "body" to redactedOAuthResponsePreview(responseText)),
                )
                throw ChatGPTOAuthException(
                    "ChatGPT token exchange failed ($status): ${responseText.take(300)}",
                )
            }

            return JSONObject(responseText)
        } finally {
            connection.disconnect()
        }
    }

    private fun formValue(body: String, name: String): String? =
        body.split("&")
            .firstOrNull { it.substringBefore("=") == name }
            ?.substringAfter("=", "")
            ?.let(Uri::decode)

    private fun jsonObjectKeys(text: String): List<String> = try {
        val payload = JSONObject(text)
        payload.keys().asSequence().toList().sorted()
    } catch (_: Exception) {
        emptyList()
    }

    private fun redactedOAuthResponsePreview(text: String): String = try {
        val payload = JSONObject(text)
        val keys = payload.keys().asSequence().toList()
        for (key in keys) {
            if (isSensitiveOAuthKey(key)) {
                payload.put(key, "<redacted>")
            }
        }
        payload.toString().take(300)
    } catch (_: Exception) {
        text.take(300)
    }

    private fun isSensitiveOAuthKey(key: String): Boolean {
        val normalized = key.replace("_", "").lowercase()
        return normalized.contains("token") || normalized.contains("authorization")
    }

    private fun validateAuthorizationCallback(callbackUri: Uri, attempt: AuthAttempt) {
        validateCallbackUri(callbackUri)
        val error = callbackUri.getQueryParameter("error")?.trim()
        if (!error.isNullOrEmpty()) {
            val description = callbackUri.getQueryParameter("error_description")?.trim()
            throw ChatGPTOAuthException(
                description?.takeIf { it.isNotEmpty() } ?: error,
            )
        }

        val state = callbackUri.getQueryParameter("state")
        if (state != attempt.state) {
            throw ChatGPTOAuthException("ChatGPT login state did not match the original request.")
        }
    }

    private fun validateCallbackUri(callbackUri: Uri) {
        if (!isCallbackUri(callbackUri)) {
            throw ChatGPTOAuthException("ChatGPT login returned an invalid callback.")
        }
    }

    private fun resolveAccountId(idClaims: JSONObject, accessClaims: JSONObject): String {
        val candidates = listOf(
            idClaims.optString("chatgpt_account_id"),
            accessClaims.optString("chatgpt_account_id"),
            idClaims.optString("organization_id"),
            accessClaims.optString("organization_id"),
        )
        return candidates.firstOrNull { it.isNotBlank() }?.trim().orEmpty()
    }

    private fun resolvePlanType(idClaims: JSONObject, accessClaims: JSONObject): String? {
        val candidates = listOf(
            accessClaims.optString("chatgpt_plan_type"),
            idClaims.optString("chatgpt_plan_type"),
        )
        return candidates.firstOrNull { it.isNotBlank() }?.trim()
    }

    private fun decodeJwtClaims(jwt: String): JSONObject {
        val parts = jwt.split(".")
        if (parts.size < 2) return JSONObject()
        return try {
            val decoded = Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            val obj = JSONObject(String(decoded, Charsets.UTF_8))
            obj.optJSONObject("https://api.openai.com/auth") ?: obj
        } catch (_: Exception) {
            JSONObject()
        }
    }

    private fun generatePkceCodeVerifier(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }

    private fun generatePkceCodeChallenge(codeVerifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(codeVerifier.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(digest, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }
}

class ChatGPTOAuthTokenStore(context: Context) {
    private val prefs = openEncryptedPrefsOrReset(context, PREFS_NAME)

    fun load(): ChatGPTOAuthTokenBundle? {
        val raw = prefs.getString(KEY_TOKENS, null) ?: return null
        return try {
            val obj = JSONObject(raw)
            ChatGPTOAuthTokenBundle(
                accessToken = obj.getString("accessToken"),
                idToken = obj.getString("idToken"),
                refreshToken = obj.optString("refreshToken").takeIf { it.isNotBlank() },
                accountId = obj.getString("accountId"),
                planType = obj.optString("planType").takeIf { it.isNotBlank() },
            )
        } catch (_: Exception) {
            null
        }
    }

    fun save(tokens: ChatGPTOAuthTokenBundle) {
        val payload = JSONObject().apply {
            put("accessToken", tokens.accessToken)
            put("idToken", tokens.idToken)
            put("accountId", tokens.accountId)
            tokens.refreshToken?.let { put("refreshToken", it) }
            tokens.planType?.let { put("planType", it) }
        }
        prefs.edit().putString(KEY_TOKENS, payload.toString()).apply()
    }

    fun clear() {
        prefs.edit().remove(KEY_TOKENS).apply()
    }

    companion object {
        private const val PREFS_NAME = "litter_chatgpt_auth"
        private const val KEY_TOKENS = "tokens"
    }
}
