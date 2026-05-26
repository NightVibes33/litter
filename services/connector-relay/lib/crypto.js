import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes
} from "node:crypto";

const ENVELOPE_VERSION = 1;

export function base64UrlEncode(value) {
  return Buffer.from(value).toString("base64url");
}

export function base64UrlDecode(value) {
  return Buffer.from(value, "base64url");
}

export function randomBase64Url(byteLength = 32) {
  return randomBytes(byteLength).toString("base64url");
}

export function pkceChallenge(verifier) {
  return createHash("sha256").update(verifier).digest("base64url");
}

export function sealJson(payload, secret, purpose) {
  const key = deriveKey(secret, purpose);
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(Buffer.from(purpose));
  const plaintext = Buffer.from(JSON.stringify(payload));
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return base64UrlEncode(JSON.stringify({
    v: ENVELOPE_VERSION,
    iv: iv.toString("base64url"),
    tag: cipher.getAuthTag().toString("base64url"),
    data: ciphertext.toString("base64url")
  }));
}

export function openJson(token, secret, purpose, maxAgeMs = 10 * 60 * 1000) {
  const envelope = JSON.parse(base64UrlDecode(token).toString("utf8"));
  if (envelope.v !== ENVELOPE_VERSION) {
    throw new Error("unsupported envelope version");
  }

  const key = deriveKey(secret, purpose);
  const decipher = createDecipheriv(
    "aes-256-gcm",
    key,
    base64UrlDecode(envelope.iv)
  );
  decipher.setAAD(Buffer.from(purpose));
  decipher.setAuthTag(base64UrlDecode(envelope.tag));
  const plaintext = Buffer.concat([
    decipher.update(base64UrlDecode(envelope.data)),
    decipher.final()
  ]);
  const payload = JSON.parse(plaintext.toString("utf8"));
  if (maxAgeMs > 0 && Number.isFinite(payload.createdAt)) {
    const ageMs = Date.now() - payload.createdAt;
    if (ageMs < 0 || ageMs > maxAgeMs) {
      throw new Error("state expired");
    }
  }
  return payload;
}

export function encryptHandoff(handoffKey, payload) {
  const rawKey = base64UrlDecode(handoffKey);
  if (rawKey.length < 32) {
    throw new Error("handoff_key must decode to at least 32 bytes");
  }
  const key = createHash("sha256").update(rawKey).digest();
  const purpose = "litter.connector.handoff.v1";
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(Buffer.from(purpose));
  const plaintext = Buffer.from(JSON.stringify(payload));
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return base64UrlEncode(JSON.stringify({
    v: ENVELOPE_VERSION,
    alg: "A256GCM",
    iv: iv.toString("base64url"),
    tag: cipher.getAuthTag().toString("base64url"),
    data: ciphertext.toString("base64url")
  }));
}

function deriveKey(secret, purpose) {
  if (!secret || secret.trim().length < 32) {
    throw new Error(`${purpose} secret is not configured`);
  }
  return createHash("sha256").update(`${purpose}:${secret}`).digest();
}
