import { describe, it } from 'node:test';
import assert from 'node:assert';
import request from 'supertest';
import { createApp } from '../app.js';

describe('Part 1 Item 5: Web Client Serving and CSP Tests', () => {
  const app = createApp();

  it('GET /app/ returns 200 and has CSP headers', async () => {
    const res = await request(app).get('/app/');
    assert.strictEqual(res.status, 200);
    const csp = res.headers['content-security-policy'];
    assert.ok(csp, 'Content-Security-Policy header must be present');
    assert.ok(csp.includes('connect-src'), 'CSP must include connect-src');
    assert.ok(csp.includes('wss:'), 'CSP must allow wss: for LiveKit');
  });

  it('GET /app redirects to /app/', async () => {
    const res = await request(app).get('/app');
    assert.ok(res.status === 301 || res.status === 302, 'Status should be 301 or 302 redirect');
    assert.strictEqual(res.headers.location, '/app/');
  });

  it('GET /app/classroom/test-class-id returns 200 (SPA deep link) with no-cache headers', async () => {
    const res = await request(app).get('/app/classroom/test-class-id');
    assert.strictEqual(res.status, 200);
    const cacheControl = res.headers['cache-control'];
    assert.ok(cacheControl, 'Cache-Control header must be present');
    assert.ok(cacheControl.includes('no-cache') || cacheControl.includes('no-store'), 'Must prevent stale cache on deep link');
    const csp = res.headers['content-security-policy'];
    assert.ok(csp, 'Content-Security-Policy header must be present');
  });
});
