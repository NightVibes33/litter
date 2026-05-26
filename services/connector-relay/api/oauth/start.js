import { randomUUID } from "node:crypto";
import { sealJson } from "../../lib/crypto.js";
import { requestBaseUrl, requestUrl, redirect, sendError } from "../../lib/http.js";
import { buildAuthorizeUrl, createPkcePair } from "../../lib/oauth.js";
import {
  getProvider,
  providerCredentials,
  relayStateSecret,
  validateAppRedirectUri
} from "../../lib/providers.js";

export default function handler(req, res) {
  if (req.method !== "GET") {
    return sendError(res, 405, "method_not_allowed", "Use GET.");
  }

  try {
    const url = requestUrl(req);
    const provider = getProvider(url.searchParams.get("provider"));
    if (!provider) {
      return sendError(res, 400, "unsupported_provider", "Unsupported OAuth provider.");
    }

    const handoffKey = url.searchParams.get("handoff_key") || "";
    if (!handoffKey) {
      return sendError(res, 400, "missing_handoff_key", "handoff_key is required.");
    }

    const appRedirectUri = validateAppRedirectUri(url.searchParams.get("app_redirect_uri"));
    const publicBaseUrl = requestBaseUrl(req);
    const redirectUri = `${publicBaseUrl}/oauth/callback`;
    const pkce = provider.pkce ? createPkcePair() : null;
    const scope = url.searchParams.get("scope") ||
      providerCredentials(provider).scope ||
      provider.defaultScope;

    const relayState = sealJson({
      provider: provider.id,
      appState: url.searchParams.get("state") || "",
      appRedirectUri,
      handoffKey,
      redirectUri,
      scope,
      codeVerifier: pkce?.verifier || "",
      nonce: randomUUID(),
      createdAt: Date.now()
    }, relayStateSecret(), "oauth-state");

    const authorizeUrl = buildAuthorizeUrl(provider, {
      redirectUri,
      state: relayState,
      scope,
      codeChallenge: pkce?.challenge
    });
    redirect(res, authorizeUrl.toString());
  } catch (error) {
    sendError(res, 500, "oauth_start_failed", error.message);
  }
}
