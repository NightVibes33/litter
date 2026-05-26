import { randomBase64Url, pkceChallenge } from "./crypto.js";
import { providerCredentials } from "./providers.js";

export function buildAuthorizeUrl(provider, options) {
  const credentials = providerCredentials(provider);
  if (!credentials.clientId) {
    throw new Error(`${provider.id} client id is not configured`);
  }

  const url = new URL(provider.authUrl);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("client_id", credentials.clientId);
  url.searchParams.set("redirect_uri", options.redirectUri);
  url.searchParams.set("state", options.state);
  const scope = options.scope || credentials.scope;
  if (scope) {
    url.searchParams.set("scope", scope);
  }
  for (const [key, value] of Object.entries(provider.extraAuthorizeParams || {})) {
    url.searchParams.set(key, value);
  }
  if (options.codeChallenge) {
    url.searchParams.set("code_challenge", options.codeChallenge);
    url.searchParams.set("code_challenge_method", "S256");
  }
  return url;
}

export function createPkcePair() {
  const verifier = randomBase64Url(48);
  return {
    verifier,
    challenge: pkceChallenge(verifier)
  };
}

export async function exchangeAuthorizationCode(provider, params) {
  return exchangeToken(provider, {
    grant_type: "authorization_code",
    code: params.code,
    redirect_uri: params.redirectUri,
    code_verifier: params.codeVerifier
  });
}

export async function exchangeRefreshToken(provider, params) {
  if (provider.refreshable === false) {
    throw new Error(`${provider.id} does not support generic refresh through this relay`);
  }
  return exchangeToken(provider, {
    grant_type: "refresh_token",
    refresh_token: params.refreshToken,
    scope: params.scope
  });
}

async function exchangeToken(provider, fields) {
  const credentials = providerCredentials(provider);
  if (!credentials.clientId) {
    throw new Error(`${provider.id} client id is not configured`);
  }
  if (provider.clientSecretRequired && !credentials.clientSecret) {
    throw new Error(`${provider.id} client secret is not configured`);
  }

  const headers = {
    accept: "application/json"
  };
  const bodyFields = {
    ...withoutEmpty(fields)
  };

  if (provider.tokenAuth === "basic") {
    headers.authorization = `Basic ${Buffer.from(
      `${credentials.clientId}:${credentials.clientSecret}`
    ).toString("base64")}`;
  } else {
    bodyFields.client_id = credentials.clientId;
    if (credentials.clientSecret) {
      bodyFields.client_secret = credentials.clientSecret;
    }
  }

  const { body, contentType } = encodeBody(provider, bodyFields);
  headers["content-type"] = contentType;

  const response = await fetch(provider.tokenUrl, {
    method: "POST",
    headers,
    body
  });
  const text = await response.text();
  const parsed = parseTokenResponse(text);
  if (!response.ok || tokenResponseFailed(provider, parsed)) {
    const description = parsed.error_description ||
      parsed.error ||
      parsed.message ||
      response.statusText ||
      "token exchange failed";
    throw new Error(`${provider.id} token exchange failed: ${description}`);
  }
  return parsed;
}

function encodeBody(provider, fields) {
  if (provider.tokenBody === "json") {
    return {
      contentType: "application/json",
      body: JSON.stringify(fields)
    };
  }
  return {
    contentType: "application/x-www-form-urlencoded",
    body: new URLSearchParams(fields).toString()
  };
}

function parseTokenResponse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return Object.fromEntries(new URLSearchParams(text));
  }
}

function tokenResponseFailed(provider, parsed) {
  if (provider.id === "slack") {
    return parsed.ok === false;
  }
  return Boolean(parsed.error);
}

function withoutEmpty(fields) {
  return Object.fromEntries(
    Object.entries(fields).filter(([, value]) => value !== undefined && value !== "")
  );
}
