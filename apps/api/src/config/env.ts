import dotenv from 'dotenv';
import { z } from 'zod';

dotenv.config();

const DENYLIST_KEYS = new Set(['devkey', 'testkey', 'default', 'example']);
const DENYLIST_SECRETS = new Set(['secret', 'devsecret', 'testsecret', 'password', 'default']);

export interface LiveKitConfigStatus {
  configured: boolean;
  urlHost: string | null;
  urlIsWss: boolean;
  usingDefaultKeys: boolean;
  reason?: string;
}

const envSchema = z.object({
  PORT: z.string().default('4000').transform((val) => parseInt(val, 10)),
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  DATABASE_URL: z.string().default('file:./dev.db'),
  JWT_ACCESS_SECRET: z.string().default('classora_super_secret_access_jwt_key_2026_change_in_prod'),
  JWT_REFRESH_SECRET: z.string().default('classora_super_secret_refresh_jwt_key_2026_change_in_prod'),
  JWT_ACCESS_EXPIRES_IN: z.string().default('15m'),
  JWT_REFRESH_EXPIRES_DAYS: z.string().default('30').transform((val) => parseInt(val, 10)),
  INVITE_TOKEN_EXPIRES_HOURS: z.string().default('48').transform((val) => parseInt(val, 10)),
  CORS_ORIGINS: z.string().default('http://localhost:3000,http://localhost:3001,http://localhost:3002,http://localhost:3003,http://localhost:5173'),
  LIVEKIT_URL: z.string().optional().default('http://localhost:7880'),
  LIVEKIT_API_KEY: z.string().optional().default('devkey'),
  LIVEKIT_API_SECRET: z.string().optional().default('secret'),
  RAZORPAY_KEY_ID: z.string().optional().default('rzp_test_placeholder'),
  RAZORPAY_KEY_SECRET: z.string().optional().default('rzp_secret_placeholder'),
  RAZORPAY_WEBHOOK_SECRET: z.string().optional().default('rzp_webhook_secret_placeholder'),
  // Public URL of the deployed server (used for self-ping keep-alive on Render)
  APP_URL: z.string().optional(),
});

export const env = envSchema.parse(process.env);

/**
 * Validates LiveKit environment configuration.
 * In production mode:
 * - LIVEKIT_URL must be provided, start with wss://, and not point to localhost/127.0.0.1
 * - LIVEKIT_API_KEY and LIVEKIT_API_SECRET must not match old development defaults / denylist
 * If validation fails in production, the server starts in degraded mode (video disabled)
 * and logs ONE line naming the problematic variable without leaking any secret values.
 */
export function getLiveKitStatus(): LiveKitConfigStatus {
  const rawUrl = env.LIVEKIT_URL?.trim() || '';
  const rawKey = env.LIVEKIT_API_KEY?.trim() || '';
  const rawSecret = env.LIVEKIT_API_SECRET?.trim() || '';

  let urlHost: string | null = null;
  let urlIsWss = false;

  if (rawUrl) {
    try {
      // Normalise wss:// to https:// so URL parser extracts hostname correctly
      const parsedUrl = new URL(rawUrl.replace(/^wss:\/\//i, 'https://').replace(/^ws:\/\//i, 'http://'));
      urlHost = parsedUrl.hostname;
      urlIsWss = /^wss:\/\//i.test(rawUrl);
    } catch {
      urlHost = null;
      urlIsWss = false;
    }
  }

  const isLocalhost = !urlHost || urlHost === 'localhost' || urlHost === '127.0.0.1' || urlHost === '::1';
  const isDefaultKey = !rawKey || DENYLIST_KEYS.has(rawKey.toLowerCase());
  const isDefaultSecret = !rawSecret || DENYLIST_SECRETS.has(rawSecret.toLowerCase());
  const usingDefaultKeys = isDefaultKey || isDefaultSecret;

  if (env.NODE_ENV === 'production') {
    if (!rawUrl) {
      return { configured: false, urlHost: null, urlIsWss: false, usingDefaultKeys, reason: 'LIVEKIT_URL is missing' };
    }
    if (!urlIsWss) {
      return { configured: false, urlHost, urlIsWss: false, usingDefaultKeys, reason: 'LIVEKIT_URL does not start with wss://' };
    }
    if (isLocalhost) {
      return { configured: false, urlHost, urlIsWss, usingDefaultKeys, reason: 'LIVEKIT_URL points to localhost loopback' };
    }
    if (!rawKey) {
      return { configured: false, urlHost, urlIsWss, usingDefaultKeys, reason: 'LIVEKIT_API_KEY is missing' };
    }
    if (isDefaultKey) {
      return { configured: false, urlHost, urlIsWss, usingDefaultKeys, reason: 'LIVEKIT_API_KEY matches insecure default' };
    }
    if (!rawSecret) {
      return { configured: false, urlHost, urlIsWss, usingDefaultKeys, reason: 'LIVEKIT_API_SECRET is missing' };
    }
    if (isDefaultSecret) {
      return { configured: false, urlHost, urlIsWss, usingDefaultKeys, reason: 'LIVEKIT_API_SECRET matches insecure default' };
    }
  }

  return {
    configured: !isLocalhost && !usingDefaultKeys && (env.NODE_ENV !== 'production' || urlIsWss),
    urlHost,
    urlIsWss,
    usingDefaultKeys,
  };
}

/**
 * Checks LiveKit configuration on startup and emits exactly one log line if degraded.
 */
export function validateLiveKitOnStartup(): void {
  const status = getLiveKitStatus();
  if (!status.configured) {
    if (env.NODE_ENV === 'production') {
      console.warn(`[LiveKit] ⚠️ Degraded mode: Video disabled (${status.reason || 'LIVEKIT_URL / keys unconfigured'}). API endpoints remain operational.`);
    } else {
      console.log(`[LiveKit] 🟢 LiveKit Cloud configured: wss://${status.urlHost}`);
    }
  }
}

export const BUILD_TIME = process.env.BUILD_TIME || new Date().toISOString();

export function getGitCommit(): string {
  const fromEnv = process.env.RENDER_GIT_COMMIT || process.env.COMMIT_SHA || process.env.GIT_COMMIT;
  if (fromEnv) return fromEnv.substring(0, 7);
  try {
    const { execSync } = require('child_process');
    const out = execSync('git rev-parse --short HEAD', { stdio: ['pipe', 'pipe', 'ignore'] }).toString().trim();
    if (out) return out;
  } catch {
    // git not available or not a git repo at runtime
  }
  return 'unknown';
}
