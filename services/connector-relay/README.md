# Litter Connector Relay

Stateless Vercel relay for connector providers that need an HTTPS OAuth
callback, client secret, or server-side token exchange.

The relay does not persist tokens. Litter starts OAuth with a per-login
`handoff_key`, the relay exchanges the provider authorization code, encrypts
the token response with that key, and redirects back to Litter. The iOS app
should store decrypted tokens in Keychain and expose provider calls to bots
through a local native connector broker.

## Endpoints

- `GET /health` - deployment and configuration readiness.
- `GET /connectors` - provider catalog and auth modes.
- `GET /oauth/start` - starts OAuth.
- `GET /oauth/callback` - provider callback target.
- `POST /oauth/refresh` - refreshes tokens for secret-required providers.

## Start OAuth

```text
GET /oauth/start
  ?provider=slack
  &state=<app-state>
  &handoff_key=<base64url-32-byte-key>
  &app_redirect_uri=litterauth://connector/callback
```

The relay redirects to the provider. On success it redirects back to:

```text
litterauth://connector/callback
  ?provider=slack
  &state=<app-state>
  &handoff_format=litter.connector.v1
  &handoff=<encrypted-token-payload>
```

## Required Vercel env

- `CONNECTOR_RELAY_STATE_SECRET`: random secret used to encrypt OAuth state.
- `CONNECTOR_RELAY_PUBLIC_BASE_URL`: optional absolute relay URL. If omitted,
  the relay infers it from Vercel request headers.
- `LITTER_ALLOWED_APP_REDIRECT_SCHEMES`: optional comma list. Defaults to
  `litterauth`.

Provider credentials are named `CONNECTOR_<PROVIDER>_CLIENT_ID` and
`CONNECTOR_<PROVIDER>_CLIENT_SECRET`, for example
`CONNECTOR_SLACK_CLIENT_ID` and `CONNECTOR_SLACK_CLIENT_SECRET`.

## Deploy

From this directory:

```sh
TOKEN="$(tr -d '\r\n' < /root/VERCEL_TOKEN)"
vercel deploy --prod --yes --token "$TOKEN"
```

Set `CONNECTOR_RELAY_STATE_SECRET` before production use.
