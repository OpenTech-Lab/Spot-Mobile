/**
 * Spot Media Presign Lambda
 *
 * Generates presigned S3 PUT URLs for media uploads.
 * Auth: Client signs "PUT:<contentHash>:<timestamp>" with their Nostr
 * (secp256k1/schnorr) private key. This function verifies the BIP-340
 * schnorr signature before issuing the presigned URL.
 *
 * Request body (POST):
 *   { pubkey, contentHash, timestamp, signature, contentType? }
 *
 * Response:
 *   { uploadUrl, contentHash, expiresIn }
 */

const { S3Client, PutObjectCommand } = require("@aws-sdk/client-s3");
const { getSignedUrl } = require("@aws-sdk/s3-request-presigner");
const { schnorr } = require("@noble/curves/secp256k1");
const crypto = require("crypto");

const BUCKET_NAME = process.env.BUCKET_NAME;
const RATE_LIMIT_PER_MINUTE = parseInt(process.env.RATE_LIMIT_PER_MINUTE || "10", 10);
const PRESIGN_EXPIRY_SECONDS = parseInt(process.env.PRESIGN_EXPIRY_SECONDS || "900", 10);
const MAX_TIMESTAMP_DRIFT_MS = 5 * 60 * 1000; // 5 minutes

const s3 = new S3Client({});

// In-memory rate limiter keyed by pubkey.
// Resets on Lambda cold start — acceptable as a first line of defense.
// For production scale, back with DynamoDB atomic counters or WAF rate rules.
const rateBuckets = new Map();

function isRateLimited(pubkey) {
  const now = Date.now();
  const windowStart = now - 60_000;

  let bucket = rateBuckets.get(pubkey);
  if (!bucket) {
    bucket = [];
    rateBuckets.set(pubkey, bucket);
  }

  while (bucket.length > 0 && bucket[0] < windowStart) {
    bucket.shift();
  }

  if (bucket.length >= RATE_LIMIT_PER_MINUTE) {
    return true;
  }

  bucket.push(now);
  return false;
}

function isValidHex(str, expectedLength) {
  if (typeof str !== "string" || str.length !== expectedLength) return false;
  return /^[0-9a-f]+$/.test(str);
}

/**
 * Verify a BIP-340 schnorr signature using @noble/curves.
 *
 * The client signs SHA-256(message) where message = "PUT:<contentHash>:<timestamp>".
 * This matches WalletService.signMessage on the Dart side which hashes with
 * SHA-256 before passing to BIP-340 _schnorrSign.
 */
function verifySignature(pubkey, message, signature) {
  if (!isValidHex(pubkey, 64)) return false;
  if (!isValidHex(signature, 128)) return false;
  if (typeof message !== "string" || message.length === 0) return false;

  try {
    const msgHash = crypto.createHash("sha256").update(message).digest();
    return schnorr.verify(signature, msgHash, pubkey);
  } catch {
    return false;
  }
}

function response(statusCode, body) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
    body: JSON.stringify(body),
  };
}

exports.handler = async (event) => {
  try {
    const body =
      typeof event.body === "string" ? JSON.parse(event.body) : event.body;

    const { pubkey, contentHash, timestamp, signature, contentType } =
      body || {};

    // ── Validate required fields ───────────────────────────────────────────

    if (!pubkey || !contentHash || !timestamp || !signature) {
      return response(400, {
        error: "Missing required fields: pubkey, contentHash, timestamp, signature",
      });
    }

    if (!isValidHex(contentHash, 64)) {
      return response(400, { error: "contentHash must be 64-char hex (SHA-256)" });
    }

    if (!isValidHex(pubkey, 64)) {
      return response(400, { error: "pubkey must be 64-char hex" });
    }

    // ── Timestamp drift check ──────────────────────────────────────────────

    const tsMs =
      typeof timestamp === "number"
        ? timestamp > 1e12
          ? timestamp
          : timestamp * 1000
        : parseInt(timestamp, 10) * 1000;

    if (isNaN(tsMs) || Math.abs(Date.now() - tsMs) > MAX_TIMESTAMP_DRIFT_MS) {
      return response(400, { error: "Timestamp too far from server time" });
    }

    // ── Rate limit (before signature check to prevent enumeration) ─────────

    if (isRateLimited(pubkey)) {
      return response(429, { error: "Rate limit exceeded" });
    }

    // ── Verify BIP-340 schnorr signature ───────────────────────────────────

    const message = `PUT:${contentHash}:${timestamp}`;
    if (!verifySignature(pubkey, message, signature)) {
      return response(403, { error: "Invalid signature" });
    }

    // ── Generate presigned PUT URL ─────────────────────────────────────────

    const resolvedContentType = contentType || "application/octet-stream";
    const key = contentHash;

    const command = new PutObjectCommand({
      Bucket: BUCKET_NAME,
      Key: key,
      ContentType: resolvedContentType,
      Metadata: {
        "uploader-pubkey": pubkey,
        "upload-timestamp": String(timestamp),
      },
    });

    const uploadUrl = await getSignedUrl(s3, command, {
      expiresIn: PRESIGN_EXPIRY_SECONDS,
    });

    return response(200, {
      uploadUrl,
      contentHash,
      expiresIn: PRESIGN_EXPIRY_SECONDS,
    });
  } catch (err) {
    console.error("Presign error:", err);
    return response(500, { error: "Internal server error" });
  }
};
