// ezcamps shared ratings API (Cloudflare Worker + D1).
//
// Reading is public. Writing needs a session from Sign in with Apple. People are stored only as an
// HMAC of their Apple user id, and ratings are shown without any name. One rating per person, per
// site, per night. Verified visits (logged on-site) weigh double and every rating fades with age, so
// "Rough road" from two weeks ago outranks a three-year-old review.

import { verifyAppleIdentityToken } from "./apple";

interface Bindings extends Omit<Env, "ALLOW_DEV_AUTH"> {
  ALLOW_DEV_AUTH?: string; // only ever set in .dev.vars
}

const TAGS = new Set([
  "Quiet", "Level spots", "Clean", "Shade", "Great views", "Dark skies", "Rough road", "Crowded", "Big-rig friendly",
]);
const CARRIERS = new Set(["AT&T", "Verizon", "T-Mobile", "Other"]);
const SITE_ID = /^[a-z]{2,8}:[A-Za-z0-9:-]{1,64}$/;
const UUID = /^[0-9a-fA-F-]{36}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;

const SESSION_DAYS = 180;
const MAX_WRITES_PER_DAY = 40;
const MAX_NOTE = 1000;
const HIDE_AFTER_REPORTS = 3;
const HALF_LIFE_DAYS = 365;
const VERIFIED_WEIGHT = 2;
const MAX_BODY = 8 * 1024;

export default {
  async fetch(request: Request, env: Bindings): Promise<Response> {
    try {
      return await route(request, env);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status);
      console.error("unhandled", e instanceof Error ? e.stack : String(e));
      return json({ error: "Something went wrong." }, 500);
    }
  },
} satisfies ExportedHandler<Bindings>;

async function route(req: Request, env: Bindings): Promise<Response> {
  const url = new URL(req.url);
  const path = url.pathname.replace(/\/+$/, "");
  const m = req.method;
  let p: RegExpMatchArray | null;

  if (m === "GET" && path === "/v1/health") return json({ ok: true });
  if (m === "POST" && path === "/v1/auth/apple") return authApple(req, env);
  if (m === "POST" && path === "/v1/auth/dev" && env.ALLOW_DEV_AUTH === "1") return authDev(req, env);
  if (m === "DELETE" && path === "/v1/account") return deleteAccount(req, env);
  if (m === "GET" && path === "/v1/summaries") return summaries(url, env);
  if (m === "GET" && (p = path.match(/^\/v1\/sites\/([^/]+)\/ratings$/))) return siteRatings(req, decodeURIComponent(p[1]), env);
  if (m === "PUT" && (p = path.match(/^\/v1\/ratings\/([^/]+)$/))) return putRating(req, p[1], env);
  if (m === "DELETE" && (p = path.match(/^\/v1\/ratings\/([^/]+)$/))) return deleteRating(req, p[1], env);
  if (m === "POST" && (p = path.match(/^\/v1\/ratings\/([^/]+)\/report$/))) return report(req, p[1], env);
  return json({ error: "Not found" }, 404);
}

// MARK: Auth

async function authApple(req: Request, env: Bindings): Promise<Response> {
  const body = await readJSON(req);
  const token = str(body.identityToken, 4096);
  if (!token) throw new HttpError(400, "identityToken is required.");
  const sub = await verifyAppleIdentityToken(token, env.APPLE_AUDIENCE);
  if (!sub) throw new HttpError(401, "Sign in with Apple couldn't be verified.");
  return startSession(env, sub);
}

/** Local testing only: a session for a made-up user. The route doesn't exist unless ALLOW_DEV_AUTH=1. */
async function authDev(req: Request, env: Bindings): Promise<Response> {
  const body = await readJSON(req);
  return startSession(env, "dev:" + (str(body.name, 40) ?? "tester"));
}

async function startSession(env: Bindings, appleSub: string): Promise<Response> {
  const appleHash = await hmac(env.SUB_PEPPER, appleSub);
  const now = Date.now();
  await env.DB.prepare("INSERT INTO users (id, apple_hash, created_at) VALUES (?, ?, ?) ON CONFLICT(apple_hash) DO NOTHING")
    .bind(crypto.randomUUID(), appleHash, now).run();
  const user = await env.DB.prepare("SELECT id FROM users WHERE apple_hash = ?").bind(appleHash).first<{ id: string }>();
  if (!user) throw new HttpError(500, "Couldn't create the account.");

  const token = randomToken();
  await env.DB.batch([
    env.DB.prepare("INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)")
      .bind(await sha256(token), user.id, now, now + SESSION_DAYS * 86_400_000),
    // Keep the newest 10 sessions per person and drop expired ones.
    env.DB.prepare(`DELETE FROM sessions WHERE user_id = ?1 AND (expires_at < ?2 OR token_hash NOT IN
                    (SELECT token_hash FROM sessions WHERE user_id = ?1 ORDER BY created_at DESC LIMIT 10))`)
      .bind(user.id, now),
  ]);
  return json({ token, expiresInDays: SESSION_DAYS });
}

async function requireUser(req: Request, env: Bindings): Promise<string> {
  const user = await optionalUser(req, env);
  if (!user) throw new HttpError(401, "Sign in to do that.");
  return user;
}

async function optionalUser(req: Request, env: Bindings): Promise<string | null> {
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (token.length < 20 || token.length > 200) return null;
  const row = await env.DB.prepare("SELECT user_id FROM sessions WHERE token_hash = ? AND expires_at > ?")
    .bind(await sha256(token), Date.now()).first<{ user_id: string }>();
  return row?.user_id ?? null;
}

/** Deletes the person and everything they wrote (ratings, reports, sessions). */
async function deleteAccount(req: Request, env: Bindings): Promise<Response> {
  const user = await requireUser(req, env);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM reports WHERE user_id = ?").bind(user),
    env.DB.prepare("DELETE FROM reports WHERE rating_id IN (SELECT id FROM ratings WHERE user_id = ?)").bind(user),
    env.DB.prepare("DELETE FROM ratings WHERE user_id = ?").bind(user),
    env.DB.prepare("DELETE FROM sessions WHERE user_id = ?").bind(user),
    env.DB.prepare("DELETE FROM users WHERE id = ?").bind(user),
  ]);
  return json({ deleted: true });
}

// MARK: Ratings

interface RatingRow {
  id: string;
  user_id: string;
  visit_date: string;
  rating: number;
  tags: string;
  note: string;
  verified: number;
  carrier: string | null;
  signal: number | null;
}

async function putRating(req: Request, id: string, env: Bindings): Promise<Response> {
  if (!UUID.test(id)) throw new HttpError(400, "Bad rating id.");
  const user = await requireUser(req, env);
  const b = await readJSON(req);

  const siteId = str(b.siteId, 80);
  if (!siteId || !SITE_ID.test(siteId)) throw new HttpError(400, "Bad site id.");
  const visitDate = str(b.visitDate, 10);
  if (!visitDate || !DAY.test(visitDate) || !isPlausibleDay(visitDate)) throw new HttpError(400, "Bad visit date.");
  const rating = Number(b.rating);
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) throw new HttpError(400, "Rating must be 1 to 5.");
  const tags = Array.isArray(b.tags) ? [...new Set(b.tags.filter((t): t is string => typeof t === "string" && TAGS.has(t)))] : [];
  const note = (typeof b.note === "string" ? b.note : "").trim().slice(0, MAX_NOTE);
  const verified = b.verified === true ? 1 : 0;
  const carrier = typeof b.carrier === "string" && CARRIERS.has(b.carrier) ? b.carrier : null;
  const signal = carrier && Number.isInteger(b.signal) && (b.signal as number) >= 0 && (b.signal as number) <= 3 ? (b.signal as number) : null;

  const now = Date.now();
  const recent = await env.DB.prepare("SELECT COUNT(*) AS n FROM ratings WHERE user_id = ? AND updated_at > ?")
    .bind(user, now - 86_400_000).first<{ n: number }>();
  if ((recent?.n ?? 0) >= MAX_WRITES_PER_DAY) throw new HttpError(429, "That's a lot of ratings for one day. Try again tomorrow.");

  const owner = await env.DB.prepare("SELECT user_id FROM ratings WHERE id = ?").bind(id).first<{ user_id: string }>();
  if (owner && owner.user_id !== user) throw new HttpError(403, "That rating belongs to someone else.");

  // Same site and night already rated (e.g. from another phone): update that one instead of adding a second.
  const sameNight = await env.DB.prepare("SELECT id FROM ratings WHERE user_id = ? AND site_id = ? AND visit_date = ?")
    .bind(user, siteId, visitDate).first<{ id: string }>();
  const targetId = sameNight && sameNight.id !== id && !owner ? sameNight.id : id;
  if (sameNight && owner && sameNight.id !== id) {
    throw new HttpError(409, "You already rated this site for that night.");
  }

  await env.DB.prepare(
    `INSERT INTO ratings (id, user_id, site_id, visit_date, rating, tags, note, verified, carrier, signal, created_at, updated_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?11)
     ON CONFLICT(id) DO UPDATE SET site_id = ?3, visit_date = ?4, rating = ?5, tags = ?6, note = ?7,
       verified = ?8, carrier = ?9, signal = ?10, updated_at = ?11`,
  ).bind(targetId, user, siteId, visitDate, rating, JSON.stringify(tags), note, verified, carrier, signal, now).run();

  return json({ id: targetId });
}

async function deleteRating(req: Request, id: string, env: Bindings): Promise<Response> {
  if (!UUID.test(id)) throw new HttpError(400, "Bad rating id.");
  const user = await requireUser(req, env);
  await env.DB.batch([
    env.DB.prepare("DELETE FROM reports WHERE rating_id = ? AND rating_id IN (SELECT id FROM ratings WHERE user_id = ?)").bind(id, user),
    env.DB.prepare("DELETE FROM ratings WHERE id = ? AND user_id = ?").bind(id, user),
  ]);
  return json({ deleted: true });
}

async function report(req: Request, id: string, env: Bindings): Promise<Response> {
  if (!UUID.test(id)) throw new HttpError(400, "Bad rating id.");
  const user = await requireUser(req, env);
  const b = await readJSON(req);
  const reason = str(b.reason, 200) ?? "Not helpful";
  const rating = await env.DB.prepare("SELECT user_id FROM ratings WHERE id = ?").bind(id).first<{ user_id: string }>();
  if (!rating) throw new HttpError(404, "Rating not found.");
  if (rating.user_id === user) throw new HttpError(400, "You can't report your own rating.");
  await env.DB.batch([
    env.DB.prepare("INSERT INTO reports (rating_id, user_id, reason, created_at) VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING")
      .bind(id, user, reason, Date.now()),
    env.DB.prepare(`UPDATE ratings SET reports = (SELECT COUNT(*) FROM reports WHERE rating_id = ?1),
                    hidden = (SELECT COUNT(*) FROM reports WHERE rating_id = ?1) >= ?2 WHERE id = ?1`)
      .bind(id, HIDE_AFTER_REPORTS),
  ]);
  return json({ reported: true });
}

// MARK: Reading

/** Score, counts, recent tags and the newest ratings for one site. Signed-in callers see which are theirs. */
async function siteRatings(req: Request, siteId: string, env: Bindings): Promise<Response> {
  if (!SITE_ID.test(siteId)) throw new HttpError(400, "Bad site id.");
  const user = await optionalUser(req, env);
  const { results } = await env.DB.prepare(
    `SELECT id, user_id, visit_date, rating, tags, note, verified, carrier, signal FROM ratings
     WHERE site_id = ? AND hidden = 0 ORDER BY visit_date DESC, updated_at DESC LIMIT 300`,
  ).bind(siteId).all<RatingRow>();

  const today = Date.now();
  const recentTags = new Map<string, { count: number; latest: string }>();
  for (const r of results) {
    if (ageDays(r.visit_date, today) > 120) continue;
    for (const t of parseTags(r.tags)) {
      const e = recentTags.get(t);
      if (!e) recentTags.set(t, { count: 1, latest: r.visit_date });
      else e.count += 1;
    }
  }

  return json({
    summary: summarize(results, today),
    recentTags: [...recentTags].map(([tag, v]) => ({ tag, count: v.count, latest: v.latest }))
      .sort((a, b) => b.count - a.count || b.latest.localeCompare(a.latest)),
    ratings: results.slice(0, 30).map((r) => ({
      id: r.id,
      visitDate: r.visit_date,
      rating: r.rating,
      tags: parseTags(r.tags),
      note: r.note,
      verified: r.verified === 1,
      carrier: r.carrier,
      signal: r.signal,
      mine: user !== null && r.user_id === user,
    })),
  }, 200, { "Cache-Control": user ? "private, no-store" : "public, max-age=60" });
}

/** Scores for many sites at once (for lists and the map): GET /v1/summaries?ids=a,b,c (max 200). */
async function summaries(url: URL, env: Bindings): Promise<Response> {
  const ids = [...new Set((url.searchParams.get("ids") ?? "").split(",").filter((s) => SITE_ID.test(s)))].slice(0, 200);
  if (ids.length === 0) return json({ summaries: {} });
  const { results } = await env.DB.prepare(
    `SELECT site_id, visit_date, rating, verified FROM ratings
     WHERE hidden = 0 AND site_id IN (SELECT value FROM json_each(?))`,
  ).bind(JSON.stringify(ids)).all<{ site_id: string; visit_date: string; rating: number; verified: number }>();
  const bySite = new Map<string, typeof results>();
  for (const r of results) (bySite.get(r.site_id) ?? bySite.set(r.site_id, []).get(r.site_id)!).push(r);
  const out: Record<string, ReturnType<typeof summarize>> = {};
  const now = Date.now();
  for (const [id, rows] of bySite) out[id] = summarize(rows, now);
  return json({ summaries: out }, 200, { "Cache-Control": "public, max-age=120" });
}

/** Weighted average: verified ×2, halving every year since the night camped. */
function summarize(rows: { visit_date: string; rating: number; verified: number }[], now: number) {
  let w = 0, sum = 0, verified = 0, latest: string | null = null;
  for (const r of rows) {
    const weight = (r.verified === 1 ? VERIFIED_WEIGHT : 1) * Math.pow(0.5, ageDays(r.visit_date, now) / HALF_LIFE_DAYS);
    w += weight;
    sum += weight * r.rating;
    if (r.verified === 1) verified += 1;
    if (!latest || r.visit_date > latest) latest = r.visit_date;
  }
  return {
    score: w > 0 ? Math.round((sum / w) * 10) / 10 : null,
    count: rows.length,
    verifiedCount: verified,
    latestVisit: latest,
  };
}

// MARK: Helpers

class HttpError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "X-Content-Type-Options": "nosniff", ...headers },
  });
}

async function readJSON(req: Request): Promise<Record<string, unknown>> {
  const len = Number(req.headers.get("Content-Length") ?? "0");
  if (len > MAX_BODY) throw new HttpError(413, "Request too large.");
  const text = await req.text();
  if (text.length > MAX_BODY) throw new HttpError(413, "Request too large.");
  try {
    const v = JSON.parse(text || "{}");
    if (v && typeof v === "object" && !Array.isArray(v)) return v as Record<string, unknown>;
  } catch { /* fall through */ }
  throw new HttpError(400, "Body must be a JSON object.");
}

function str(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t.length > 0 && t.length <= max ? t : null;
}

function parseTags(raw: string): string[] {
  try {
    const v = JSON.parse(raw);
    return Array.isArray(v) ? v.filter((t) => typeof t === "string") : [];
  } catch {
    return [];
  }
}

function ageDays(day: string, now: number): number {
  return Math.max(0, (now - Date.parse(day + "T00:00:00Z")) / 86_400_000);
}

/** A real calendar day, not in the future (one day of slack for time zones), not before 2000. */
function isPlausibleDay(day: string): boolean {
  const t = Date.parse(day + "T00:00:00Z");
  return Number.isFinite(t) && new Date(t).toISOString().startsWith(day) && t <= Date.now() + 86_400_000 && t >= Date.UTC(2000, 0, 1);
}

function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256(s: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
}

async function hmac(key: string, s: string): Promise<string> {
  if (!key) throw new HttpError(500, "Server isn't configured.");
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(s)));
}

function hex(buf: ArrayBuffer): string {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
