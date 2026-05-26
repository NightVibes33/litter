export function sendJson(res, statusCode, body) {
  res.statusCode = statusCode;
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.setHeader("cache-control", "no-store");
  res.end(JSON.stringify(body, null, 2));
}

export function sendError(res, statusCode, code, message, extra = {}) {
  sendJson(res, statusCode, {
    ok: false,
    error: {
      code,
      message,
      ...extra
    }
  });
}

export function requireMethod(req, res, method) {
  if (req.method === method) {
    return true;
  }
  res.setHeader("allow", method);
  sendError(res, 405, "method_not_allowed", `Use ${method}.`);
  return false;
}

export function requestBaseUrl(req) {
  if (process.env.CONNECTOR_RELAY_PUBLIC_BASE_URL) {
    return process.env.CONNECTOR_RELAY_PUBLIC_BASE_URL.replace(/\/+$/, "");
  }
  const proto = req.headers["x-forwarded-proto"] || "https";
  const host = req.headers["x-forwarded-host"] || req.headers.host;
  return `${proto}://${host}`;
}

export function requestUrl(req) {
  return new URL(req.url, requestBaseUrl(req));
}

export function redirect(res, location) {
  res.statusCode = 302;
  res.setHeader("location", location);
  res.setHeader("cache-control", "no-store");
  res.end("Redirecting");
}

export function appendParams(uri, params) {
  const url = new URL(uri);
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "") {
      url.searchParams.set(key, String(value));
    }
  }
  return url.toString();
}

export async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(Buffer.from(chunk));
  }
  if (chunks.length === 0) {
    return {};
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}
