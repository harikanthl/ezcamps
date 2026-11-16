// End-to-end checks against a running Worker (default: `npm run dev` on :8787 with .dev.vars).
//   BASE=http://localhost:8787 npm test
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

const BASE = process.env.BASE ?? "http://localhost:8787";
const site = "osm:test-" + Date.now();
const today = new Date().toISOString().slice(0, 10);

async function call(method, path, { token, body } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return { status: res.status, body: await res.json() };
}
const signIn = async (name) => (await call("POST", "/v1/auth/dev", { body: { name } })).body.token;

test("health", async () => {
  assert.equal((await call("GET", "/v1/health")).status, 200);
});

test("writing needs a session; bad Apple tokens are rejected", async () => {
  assert.equal((await call("PUT", `/v1/ratings/${randomUUID()}`, { body: { siteId: site } })).status, 401);
  assert.equal((await call("POST", "/v1/auth/apple", { body: { identityToken: "a.b.c" } })).status, 401);
});

test("rate, one per night, weighted summary, report and hide, delete account", async () => {
  const alice = await signIn("alice-" + site), bob = await signIn("bob-" + site);
  const r1 = randomUUID();
  const put = (token, id, extra) => call("PUT", `/v1/ratings/${id}`, { token, body: { siteId: site, visitDate: today, rating: 5, tags: ["Quiet", "Bogus"], note: "  Great  ", verified: true, ...extra } });

  assert.deepEqual((await put(alice, r1)).body, { id: r1 });
  // Same night from another phone (new id): updates the existing rating rather than adding one.
  assert.deepEqual((await put(alice, randomUUID(), { rating: 4 })).body, { id: r1 });
  // Someone else can't overwrite it.
  assert.equal((await put(bob, r1)).status, 403);
  await put(bob, randomUUID(), { rating: 1, verified: false, tags: ["Rough road"] });

  const view = (await call("GET", `/v1/sites/${encodeURIComponent(site)}/ratings`, { token: alice })).body;
  assert.equal(view.summary.count, 2);
  assert.equal(view.summary.verifiedCount, 1);
  assert.equal(view.summary.score, 3); // (4×2 + 1×1) / 3
  const mine = view.ratings.find((r) => r.mine);
  assert.deepEqual(mine.tags, ["Quiet"]); // unknown tags dropped
  assert.equal(mine.note, "Great");
  assert.ok(!("user_id" in mine) && !("userId" in mine));

  // Validation
  assert.equal((await put(alice, randomUUID(), { visitDate: "2999-01-01" })).status, 400);
  assert.equal((await put(alice, randomUUID(), { rating: 9 })).status, 400);
  assert.equal((await call("PUT", `/v1/ratings/${randomUUID()}`, { token: alice, body: { siteId: "../etc", visitDate: today, rating: 3 } })).status, 400);

  // Can't report your own; three reports hide a rating.
  assert.equal((await call("POST", `/v1/ratings/${r1}/report`, { token: alice, body: {} })).status, 400);
  for (const n of ["c", "d", "e"]) {
    await call("POST", `/v1/ratings/${r1}/report`, { token: await signIn(n + site), body: { reason: "spam" } });
  }
  const after = (await call("GET", `/v1/sites/${encodeURIComponent(site)}/ratings`)).body;
  assert.equal(after.summary.count, 1);

  const sum = (await call("GET", `/v1/summaries?ids=${encodeURIComponent(site)},osm:none`)).body;
  assert.equal(sum.summaries[site].count, 1);

  // Account deletion removes their ratings and invalidates the session.
  assert.equal((await call("DELETE", "/v1/account", { token: bob })).status, 200);
  assert.equal((await call("GET", `/v1/sites/${encodeURIComponent(site)}/ratings`)).body.summary.count, 0);
  assert.equal((await call("DELETE", `/v1/ratings/${r1}`, { token: bob })).status, 401);
});
