import express, { Express } from 'express';
import helmet from 'helmet';
import cors from 'cors';
import path from 'path';
import fs from 'fs';
import { env } from './config/env.js';
import { errorHandler } from './middlewares/errorHandler.js';
import { apiLimiter } from './middlewares/rateLimiter.js';
import routes from './routes/index.js';
import { AppError } from './errors/AppError.js';

export function createApp(): Express {
  const app = express();

  // Trust first proxy (Cloudflare tunnel, reverse proxies)
  app.set('trust proxy', 1);

  // 1. Security Headers with CSP allowing API & LiveKit WebSocket
  const livekitWss = env.LIVEKIT_URL ? env.LIVEKIT_URL.replace(/^http/, 'ws') : 'wss:';
  app.use(
    helmet({
      contentSecurityPolicy: {
        directives: {
          defaultSrc: ["'self'"],
          connectSrc: ["'self'", "https:", "wss:", livekitWss],
          scriptSrc: ["'self'", "'unsafe-inline'", "'unsafe-eval'", "'wasm-unsafe-eval'", "https://fonts.googleapis.com"],
          styleSrc: ["'self'", "'unsafe-inline'", "https://fonts.googleapis.com"],
          fontSrc: ["'self'", "https://fonts.gstatic.com", "data:"],
          imgSrc: ["'self'", "data:", "blob:", "https:"],
          workerSrc: ["'self'", "blob:"],
        },
      },
    })
  );

  // 2. CORS Allowlist
  const allowedOrigins = env.CORS_ORIGINS.split(',').map((o) => o.trim());
  app.use(
    cors({
      origin: (origin, callback) => {
        // Allow mobile apps, postman, and localhost without origin header
        if (!origin || allowedOrigins.includes(origin) || env.NODE_ENV !== 'production') {
          callback(null, true);
        } else {
          callback(new AppError('FORBIDDEN', 'Blocked by CORS policy', 403));
        }
      },
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization', 'X-Device-Id'],
    })
  );

  // 3. Body parsers
  app.use(express.json({ limit: '5mb' }));
  app.use(express.urlencoded({ extended: true, limit: '5mb' }));

  // 4. General API Rate Limiting (exclude health checks)
  app.use('/api', (req, res, next) => {
    if (req.path === '/health') return next();
    return apiLimiter(req, res, next);
  });

  // 4b. Gracefully handle duplicate /api prefix (e.g. /api/api/v1/...) from nested client base URLs
  app.use((req, _res, next) => {
    if (req.url.startsWith('/api/api/')) {
      req.url = req.url.substring(4);
    }
    next();
  });

  // 5. API Routes
  app.use('/api', routes);

  // 6. Serve Web Admin Console
  const candidatePaths = [
    path.resolve(process.cwd(), 'admin-dist'),
    path.resolve(process.cwd(), '../admin-dist'),
    path.resolve(process.cwd(), '../../_archive/admin/dist'),
    path.resolve(process.cwd(), '../_archive/admin/dist'),
    path.resolve(process.cwd(), '_archive/admin/dist'),
  ];
  const adminDist = candidatePaths.find((p) => fs.existsSync(p));
  if (adminDist) {
    app.use('/admin', express.static(adminDist));
    app.get('/admin', (_req, res) => {
      res.redirect('/admin/');
    });
    app.get('/admin/*', (_req, res) => {
      res.sendFile(path.join(adminDist, 'index.html'));
    });
  }

  // 6b. Serve Flutter Web App (/app)
  const webDistCandidates = [
    path.resolve(process.cwd(), 'web-dist'),
    path.resolve(process.cwd(), '../api/web-dist'),
    path.resolve(process.cwd(), 'apps/api/web-dist'),
    path.resolve(process.cwd(), '../mobile_flutter/build/web'),
    path.resolve(process.cwd(), 'apps/mobile_flutter/build/web'),
  ];
  const webDist = webDistCandidates.find((p) => fs.existsSync(p));
  if (webDist) {
    app.use(
      '/app',
      express.static(webDist, {
        setHeaders: (res, filePath) => {
          if (
            filePath.endsWith('.html') ||
            filePath.endsWith('flutter_service_worker.js') ||
            filePath.endsWith('main.dart.js')
          ) {
            res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
          } else {
            res.setHeader('Cache-Control', 'public, max-age=3600');
          }
        },
      })
    );
    app.get('/app', (_req, res) => {
      res.redirect('/app/');
    });
    app.get('/app/*', (_req, res) => {
      res.setHeader('Cache-Control', 'no-cache, no-store, must-revalidate');
      res.sendFile(path.join(webDist, 'index.html'));
    });
  }

  // 7. 404 Catch-All
  app.use((_req, _res, next) => {
    next(new AppError('NOT_FOUND', 'The requested resource was not found on this server', 404));
  });

  // 8. Global Error Handler
  app.use(errorHandler);

  return app;
}

export default createApp;
