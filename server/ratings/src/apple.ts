// Verifies a Sign in with Apple identity token (an RS256 JWT) against Apple's published keys.
// Returns Apple's stable user id (`sub`) when the token is genuine, for this app, and unexpired.

const APPLE_ISSUER = "https://appleid.apple.com";
const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";

interface JWK { kid: string; kty: string; alg: string; n: string; e: string; use?: string }

let cachedKeys: { keys: JWK[]; fetchedAt: number } | null = null;

async function appleKeys(forceRefresh = false): Promise<JWK[]> {
  if (!forceRefresh && cachedKeys && Date.now() - cachedKeys.fetchedAt < 6 * 3600_000) return cachedKeys.keys;
  const res = await fetch(APPLE_KEYS_URL, { cf: { cacheTtl: 3600, cacheEverything: true } });
  if (!res.ok) throw new Error(`Apple keys: ${res.status}`);
  const body = (await res.json()) as { keys?: JWK[] };
  cachedKeys = { keys: body.keys ?? [], fetchedAt: Date.now() };
  return cachedKeys.keys;
}

export async function verifyAppleIdentityToken(token: string, audience: string): Promise<string | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [h, p, s] = parts;
  let header: { alg?: string; kid?: string };
  let payload: { iss?: string; aud?: string | string[]; exp?: number; iat?: number; sub?: string };
  try {
    header = JSON.parse(b64urlText(h));
    payload = JSON.parse(b64urlText(p));
  } catch {
    return null;
  }
  if (header.alg !== "RS256" || !header.kid) return null;

  // Apple rotates keys; refetch once if the kid is new to us.
  let jwk = (await appleKeys()).find((k) => k.kid === header.kid);
  if (!jwk) jwk = (await appleKeys(true)).find((k) => k.kid === header.kid);
  if (!jwk || jwk.kty !== "RSA") return null;

  const key = await crypto.subtle.importKey(
    "jwk", { kty: "RSA", n: jwk.n, e: jwk.e, alg: "RS256", ext: true },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"],
  );
  const ok = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, b64urlBytes(s), new TextEncoder().encode(`${h}.${p}`));
  if (!ok) return null;

  const now = Math.floor(Date.now() / 1000);
  const auds = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (payload.iss !== APPLE_ISSUER) return null;
  if (!auds.includes(audience)) return null;
  if (typeof payload.exp !== "number" || payload.exp < now - 60) return null;
  if (typeof payload.iat === "number" && payload.iat > now + 300) return null;
  if (typeof payload.sub !== "string" || payload.sub.length < 6 || payload.sub.length > 128) return null;
  return payload.sub;
}

function b64urlBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function b64urlText(s: string): string {
  return new TextDecoder().decode(b64urlBytes(s));
}

// MARK: Token exchange and revocation (account deletion)

export interface AppleKeys {
  teamId: string;
  keyId: string;
  /** The .p8 file's contents (PKCS#8 PEM). */
  p8: string;
  clientId: string;
}

/** The ES256 client secret Apple wants on /auth/token and /auth/revoke, valid for 5 minutes. */
async function clientSecret(k: AppleKeys): Promise<string> {
  const pem = k.p8.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const head = enc({ alg: "ES256", kid: k.keyId });
  const body = enc({ iss: k.teamId, iat: now, exp: now + 300, aud: APPLE_ISSUER, sub: k.clientId });
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${head}.${body}`));
  return `${head}.${body}.${b64url(new Uint8Array(sig))}`;
}

/** Trades the one-time authorization code from the app for a refresh token (null on any failure). */
export async function exchangeAuthorizationCode(code: string, k: AppleKeys): Promise<string | null> {
  const res = await fetch(`${APPLE_ISSUER}/auth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: k.clientId, client_secret: await clientSecret(k), code, grant_type: "authorization_code" }),
  });
  if (!res.ok) return null;
  const out = (await res.json()) as { refresh_token?: string };
  return out.refresh_token ?? null;
}

/** Revokes ezcamp's Sign in with Apple grant for this person. Best effort: true when Apple accepted. */
export async function revokeRefreshToken(token: string, k: AppleKeys): Promise<boolean> {
  const res = await fetch(`${APPLE_ISSUER}/auth/revoke`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: k.clientId, client_secret: await clientSecret(k), token, token_type_hint: "refresh_token" }),
  });
  return res.ok;
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
