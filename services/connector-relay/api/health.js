import { sendJson } from "../lib/http.js";
import {
  connectorCatalog,
  oauthProviders,
  providerSnapshot,
  relayStateSecret
} from "../lib/providers.js";

export default function handler(req, res) {
  const stateSecretConfigured = relayStateSecret().trim().length >= 32;
  const providers = Object.values(oauthProviders).map(providerSnapshot);
  sendJson(res, 200, {
    ok: true,
    service: "litter-connector-relay",
    version: 1,
    ready: stateSecretConfigured,
    stateSecretConfigured,
    configuredProviderCount: providers.filter((provider) => provider.configured).length,
    providerCount: providers.length,
    connectorCount: connectorCatalog.length
  });
}
