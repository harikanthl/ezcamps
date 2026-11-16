-- Apple refresh token (AES-GCM encrypted with TOKEN_KEY), kept only so account deletion can revoke
-- Sign in with Apple, as App Review expects.
ALTER TABLE users ADD COLUMN apple_refresh TEXT;
