import { readJson, requireMethod, sendError, sendJson } from "../../lib/http.js";
import { exchangeRefreshToken } from "../../lib/oauth.js";
import { getProvider } from "../../lib/providers.js";

export default async function handler(req, res) {
  if (!requireMethod(req, res, "POST")) {
    return;
  }

  try {
    const body = await readJson(req);
    const provider = getProvider(body.provider);
    if (!provider) {
      return sendError(res, 400, "unsupported_provider", "Unsupported OAuth provider.");
    }
    if (!body.refresh_token) {
      return sendError(res, 400, "missing_refresh_token", "refresh_token is required.");
    }

    const token = await exchangeRefreshToken(provider, {
      refreshToken: body.refresh_token,
      scope: body.scope
    });
    sendJson(res, 200, {
      ok: true,
      provider: provider.id,
      received_at: new Date().toISOString(),
      expires_at: expiresAt(token),
      token
    });
  } catch (error) {
    sendError(res, 500, "refresh_failed", error.message);
  }
}

function expiresAt(tokenResponse) {
  const expiresIn = Number(tokenResponse.expires_in);
  if (!Number.isFinite(expiresIn) || expiresIn <= 0) {
    return null;
  }
  return new Date(Date.now() + expiresIn * 1000).toISOString();
}
