import { sendJson } from "../lib/http.js";
import {
  appRedirectDefault,
  connectorCatalog,
  oauthProviders,
  providerSnapshot,
  relayStateSecret
} from "../lib/providers.js";

export default function handler(req, res) {
  const providers = Object.values(oauthProviders).map(providerSnapshot);
  sendJson(res, 200, {
    ok: true,
    version: 1,
    relayMode: "stateless-encrypted-handoff",
    stateSecretConfigured: relayStateSecret().trim().length >= 32,
    defaultAppRedirectUri: appRedirectDefault(),
    connectors: connectorCatalog,
    providers
  });
}
