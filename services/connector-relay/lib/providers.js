const DEFAULT_APP_REDIRECT_SCHEME = "litterauth";
const DEFAULT_APP_REDIRECT_URI = "litterauth://connector/callback";

export const oauthProviders = {
  github: {
    id: "github",
    name: "GitHub",
    authUrl: "https://github.com/login/oauth/authorize",
    tokenUrl: "https://github.com/login/oauth/access_token",
    defaultScope: "repo read:user user:email",
    tokenAuth: "body",
    tokenBody: "form",
    pkce: false,
    clientSecretRequired: true
  },
  google: {
    id: "google",
    name: "Google",
    authUrl: "https://accounts.google.com/o/oauth2/v2/auth",
    tokenUrl: "https://oauth2.googleapis.com/token",
    defaultScope: [
      "openid",
      "email",
      "profile",
      "https://www.googleapis.com/auth/drive.metadata.readonly",
      "https://www.googleapis.com/auth/gmail.readonly"
    ].join(" "),
    extraAuthorizeParams: {
      access_type: "offline",
      prompt: "consent"
    },
    tokenAuth: "body",
    tokenBody: "form",
    pkce: true,
    clientSecretRequired: false
  },
  microsoft: {
    id: "microsoft",
    name: "Microsoft",
    authUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
    tokenUrl: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
    defaultScope: "offline_access User.Read Mail.Read Files.Read.All Sites.Read.All",
    tokenAuth: "body",
    tokenBody: "form",
    pkce: true,
    clientSecretRequired: false
  },
  slack: {
    id: "slack",
    name: "Slack",
    authUrl: "https://slack.com/oauth/v2/authorize",
    tokenUrl: "https://slack.com/api/oauth.v2.access",
    defaultScope: "channels:read chat:write users:read",
    tokenAuth: "body",
    tokenBody: "form",
    pkce: false,
    clientSecretRequired: true,
    refreshable: false
  },
  notion: {
    id: "notion",
    name: "Notion",
    authUrl: "https://api.notion.com/v1/oauth/authorize",
    tokenUrl: "https://api.notion.com/v1/oauth/token",
    defaultScope: "",
    tokenAuth: "basic",
    tokenBody: "json",
    pkce: false,
    clientSecretRequired: true
  },
  canva: {
    id: "canva",
    name: "Canva",
    authUrl: "https://www.canva.com/api/oauth/authorize",
    tokenUrl: "https://api.canva.com/rest/v1/oauth/token",
    defaultScope: "design:content:read design:content:write",
    tokenAuth: "basic",
    tokenBody: "form",
    pkce: true,
    clientSecretRequired: true
  },
  figma: {
    id: "figma",
    name: "Figma",
    authUrl: "https://www.figma.com/oauth",
    tokenUrl: "https://api.figma.com/v1/oauth/token",
    defaultScope: "files:read",
    tokenAuth: "body",
    tokenBody: "form",
    pkce: false,
    clientSecretRequired: true
  },
  linear: {
    id: "linear",
    name: "Linear",
    authUrl: "https://linear.app/oauth/authorize",
    tokenUrl: "https://api.linear.app/oauth/token",
    defaultScope: "read write issues:create",
    tokenAuth: "body",
    tokenBody: "form",
    pkce: false,
    clientSecretRequired: true
  }
};

export const connectorCatalog = [
  { id: "github", name: "GitHub", provider: "github", authMode: "vercelRelay" },
  { id: "gmail", name: "Gmail", provider: "google", authMode: "vercelRelay" },
  { id: "google-drive", name: "Google Drive", provider: "google", authMode: "vercelRelay" },
  { id: "slack", name: "Slack", provider: "slack", authMode: "vercelRelay" },
  { id: "notion", name: "Notion", provider: "notion", authMode: "vercelRelay" },
  { id: "linear", name: "Linear", provider: "linear", authMode: "vercelRelay" },
  { id: "figma", name: "Figma", provider: "figma", authMode: "vercelRelay" },
  { id: "canva", name: "Canva", provider: "canva", authMode: "vercelRelay" },
  { id: "outlook", name: "Outlook", provider: "microsoft", authMode: "vercelRelay" },
  { id: "teams", name: "Teams", provider: "microsoft", authMode: "vercelRelay" },
  { id: "sharepoint", name: "SharePoint", provider: "microsoft", authMode: "vercelRelay" },
  { id: "vercel", name: "Vercel", provider: null, authMode: "manualToken" },
  { id: "openai-developers", name: "OpenAI Developers", provider: null, authMode: "manualToken" }
];

export function getProvider(providerId) {
  const key = String(providerId || "").toLowerCase();
  return oauthProviders[key] || null;
}

export function providerEnv(provider, suffix) {
  return process.env[`CONNECTOR_${provider.id.toUpperCase()}_${suffix}`] || "";
}

export function providerCredentials(provider) {
  return {
    clientId: providerEnv(provider, "CLIENT_ID"),
    clientSecret: providerEnv(provider, "CLIENT_SECRET"),
    scope: providerEnv(provider, "SCOPES") || provider.defaultScope
  };
}

export function providerSnapshot(provider) {
  const credentials = providerCredentials(provider);
  const clientIdConfigured = credentials.clientId.length > 0;
  const clientSecretConfigured = credentials.clientSecret.length > 0;
  const ready = clientIdConfigured &&
    (!provider.clientSecretRequired || clientSecretConfigured);
  return {
    id: provider.id,
    name: provider.name,
    authMode: "vercelRelay",
    configured: ready,
    clientIdConfigured,
    clientSecretRequired: provider.clientSecretRequired,
    clientSecretConfigured,
    pkce: provider.pkce,
    refreshable: provider.refreshable !== false,
    defaultScope: credentials.scope
  };
}

export function appRedirectDefault() {
  return process.env.LITTER_DEFAULT_APP_REDIRECT_URI || DEFAULT_APP_REDIRECT_URI;
}

export function validateAppRedirectUri(value) {
  const uri = value || appRedirectDefault();
  let parsed;
  try {
    parsed = new URL(uri);
  } catch {
    throw new Error("invalid app_redirect_uri");
  }

  const exact = splitEnv("LITTER_ALLOWED_APP_REDIRECT_URIS");
  if (exact.length > 0 && exact.includes(uri)) {
    return uri;
  }

  const schemes = splitEnv("LITTER_ALLOWED_APP_REDIRECT_SCHEMES");
  const allowedSchemes = schemes.length > 0 ? schemes : [DEFAULT_APP_REDIRECT_SCHEME];
  const scheme = parsed.protocol.replace(/:$/, "");
  if (!allowedSchemes.includes(scheme)) {
    throw new Error("app_redirect_uri scheme is not allowed");
  }
  return uri;
}

export function relayStateSecret() {
  return process.env.CONNECTOR_RELAY_STATE_SECRET || "";
}

function splitEnv(name) {
  return String(process.env[name] || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
}
