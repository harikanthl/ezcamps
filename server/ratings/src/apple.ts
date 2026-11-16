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
