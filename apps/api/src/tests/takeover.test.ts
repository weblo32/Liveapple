import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import request from 'supertest';
import { io as Client, Socket } from 'socket.io-client';
import { Server } from 'socket.io';
import { createApp } from '../app.js';
import { setupSocketGateway, resetSocketGatewayState } from '../gateway/socket.js';
import { initializePrisma } from '../utils/prisma.js';

describe('Part 1 Item 4: One Device Per User Takeover Test', () => {
  const app = createApp();
  let server: http.Server;
  let serverPort: number;
  let studentToken: string;
  let deviceASocket: Socket;
  let deviceBSocket: Socket;
  let ioServer: Server;
  const testClassId = 'class-demo-phy-01';

  before(async () => {
    await initializePrisma();

    server = http.createServer(app);
    ioServer = new Server(server, { cors: { origin: '*' } });
    setupSocketGateway(ioServer);

    await new Promise<void>((resolve) => {
      server.listen(0, () => {
        const addr = server.address();
        if (typeof addr === 'object' && addr !== null) {
          serverPort = addr.port;
        }
        server.unref();
        resolve();
      });
    });

    const loginRes = await request(app).post('/api/v1/auth/login').send({
      email: 'student1@apex.edu',
      password: 'Password@123',
    });
    studentToken = loginRes.body.accessToken;

    deviceASocket = Client(`http://localhost:${serverPort}`, {
      auth: { token: studentToken },
      transports: ['websocket'],
    });

    await new Promise<void>((res) => deviceASocket.on('connect', () => res()));
    deviceASocket.emit('class:join', { classId: testClassId });
    await new Promise((r) => setTimeout(r, 100));
  });

  after(() => {
    deviceASocket?.disconnect();
    deviceBSocket?.disconnect();
    ioServer?.close();
    server?.close();
    resetSocketGatewayState();
  });

  it('Device B connects with same user token -> Device A receives class:takeover message', async () => {
    const takeoverPromise = new Promise<{ reason: string }>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for class:takeover on Device A')), 4000);
      deviceASocket.on('class:takeover', (data: any) => {
        clearTimeout(timer);
        resolve(data);
      });
    });

    // Device B joins same class with same student token
    deviceBSocket = Client(`http://localhost:${serverPort}`, {
      auth: { token: studentToken },
      transports: ['websocket'],
    });

    await new Promise<void>((res) => deviceBSocket.on('connect', () => res()));
    deviceBSocket.emit('class:join', { classId: testClassId });

    const takeoverData = await takeoverPromise;
    assert.ok(takeoverData.reason, 'Takeover event should have a reason');
    assert.strictEqual(
      takeoverData.reason,
      'Aap dusre device se join ho gaye',
      'Takeover message must match exact Hindi requirement'
    );
  });
});
