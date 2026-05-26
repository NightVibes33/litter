import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import startOAuth from "../api/oauth/start.js";
import { encryptHandoff, openJson, sealJson } from "../lib/crypto.js";
import { connectorCatalog, getProvider, oauthProviders } from "../lib/providers.js";

const secret = "test-state-secret-value-that-is-long-enough";
const state = {
  provider: "github",
  appState: "app-state",
  handoffKey: randomBytes(32).toString("base64url"),
  createdAt: Date.now()
};

const sealed = sealJson(state, secret, "oauth-state");
assert.deepEqual(openJson(sealed, secret, "oauth-state"), state);

const handoff = encryptHandoff(state.handoffKey, {
  provider: "github",
  token: {
    access_token: "redacted"
  }
});
assert.equal(typeof handoff, "string");
assert.ok(handoff.length > 32);

for (const id of ["github", "google", "microsoft", "slack", "notion", "canva", "figma", "linear"]) {
  assert.ok(getProvider(id), `missing provider ${id}`);
}

assert.ok(Object.keys(oauthProviders).length >= 8);
assert.ok(connectorCatalog.some((connector) => connector.id === "gmail"));
assert.ok(connectorCatalog.some((connector) => connector.id === "vercel" && connector.authMode === "manualToken"));

process.env.CONNECTOR_RELAY_STATE_SECRET = secret;
process.env.CONNECTOR_GITHUB_CLIENT_ID = "github-client-id";
process.env.CONNECTOR_GITHUB_CLIENT_SECRET = "github-client-secret";
const startResponse = mockResponse();
startOAuth({
  method: "GET",
  headers: {
    host: "relay.example.test",
    "x-forwarded-proto": "https"
  },
  url: `/oauth/start?provider=github&state=abc&handoff_key=${state.handoffKey}`
}, startResponse);
assert.equal(startResponse.statusCode, 302);
assert.match(startResponse.headers.location, /^https:\/\/github\.com\/login\/oauth\/authorize\?/);
assert.ok(new URL(startResponse.headers.location).searchParams.get("state"));

console.log("connector relay smoke test passed");

function mockResponse() {
  return {
    statusCode: 200,
    headers: {},
    body: "",
    setHeader(name, value) {
      this.headers[name.toLowerCase()] = value;
    },
    end(value = "") {
      this.body += value;
    }
  };
}
