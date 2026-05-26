import { encryptHandoff, openJson } from "../../lib/crypto.js";
import {
  appendParams,
  redirect,
  requestUrl,
  sendError
} from "../../lib/http.js";
import { exchangeAuthorizationCode } from "../../lib/oauth.js";
import { getProvider, relayStateSecret } from "../../lib/providers.js";

export default async function handler(req, res) {
  if (req.method !== "GET") {
    return sendError(res, 405, "method_not_allowed", "Use GET.");
  }

  const url = requestUrl(req);
  const sealedState = url.searchParams.get("state");
  if (!sealedState) {
    return sendError(res, 400, "missing_state", "Missing OAuth state.");
  }

  let relayState;
  try {
    relayState = openJson(sealedState, relayStateSecret(), "oauth-state");
  } catch (error) {
    return sendError(res, 400, "invalid_state", error.message);
  }

  const provider = getProvider(relayState.provider);
  if (!provider) {
    return redirectError(res, relayState, "unsupported_provider", "Unsupported OAuth provider.");
  }

  const providerError = url.searchParams.get("error");
  if (providerError) {
    return redirectError(
      res,
      relayState,
      providerError,
      url.searchParams.get("error_description") || providerError
    );
  }

  const code = url.searchParams.get("code");
  if (!code) {
    return redirectError(res, relayState, "missing_code", "Provider callback did not include code.");
  }

  try {
    const tokenResponse = await exchangeAuthorizationCode(provider, {
      code,
      redirectUri: relayState.redirectUri,
      codeVerifier: relayState.codeVerifier
    });
    const handoff = encryptHandoff(relayState.handoffKey, {
      v: 1,
      provider: provider.id,
      state: relayState.appState,
      scope: relayState.scope,
      received_at: new Date().toISOString(),
      expires_at: expiresAt(tokenResponse),
      token: tokenResponse
    });
    redirect(res, appendParams(relayState.appRedirectUri, {
      provider: provider.id,
      state: relayState.appState,
      handoff_format: "litter.connector.v1",
      handoff
    }));
  } catch (error) {
    redirectError(res, relayState, "token_exchange_failed", error.message);
  }
}

function redirectError(res, relayState, code, message) {
  redirect(res, appendParams(
    relayState.appRedirectUri,
    {
      provider: relayState.provider,
      state: relayState.appState,
      error: code,
      error_description: message
    }
  ));
}

function expiresAt(tokenResponse) {
  const expiresIn = Number(tokenResponse.expires_in);
  if (!Number.isFinite(expiresIn) || expiresIn <= 0) {
    return null;
  }
  return new Date(Date.now() + expiresIn * 1000).toISOString();
}
