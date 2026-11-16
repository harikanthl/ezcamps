-- Shared campsite ratings for ezcamps.
-- People are identified only by an HMAC of their Apple user id: no names, no emails.

CREATE TABLE users (
  id          TEXT PRIMARY KEY,               -- random, never the Apple id
  apple_hash  TEXT NOT NULL UNIQUE,           -- HMAC-SHA256(SUB_PEPPER, apple sub)
  created_at  INTEGER NOT NULL
);

CREATE TABLE sessions (
  token_hash  TEXT PRIMARY KEY,               -- SHA-256 of the bearer token; the token itself is never stored
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER NOT NULL
);
CREATE INDEX sessions_user ON sessions(user_id);

CREATE TABLE ratings (
  id          TEXT PRIMARY KEY,               -- client-generated UUID
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  site_id     TEXT NOT NULL,
  visit_date  TEXT NOT NULL,                  -- yyyy-mm-dd, the night camped
  rating      INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
  tags        TEXT NOT NULL DEFAULT '[]',     -- JSON array of known tags
  note        TEXT NOT NULL DEFAULT '',
  verified    INTEGER NOT NULL DEFAULT 0,     -- logged within 500 m of the site (checked on the phone)
  carrier     TEXT,
  signal      INTEGER CHECK (signal BETWEEN 0 AND 3),
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  reports     INTEGER NOT NULL DEFAULT 0,
  hidden      INTEGER NOT NULL DEFAULT 0,
  UNIQUE (user_id, site_id, visit_date)       -- one rating per site per night
);
CREATE INDEX ratings_site ON ratings(site_id, hidden, visit_date DESC);
CREATE INDEX ratings_user_day ON ratings(user_id, created_at);

CREATE TABLE reports (
  rating_id   TEXT NOT NULL REFERENCES ratings(id) ON DELETE CASCADE,
  user_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason      TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  PRIMARY KEY (rating_id, user_id)
);
