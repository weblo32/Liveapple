import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import request from 'supertest';
import { io as Client, Socket } from 'socket.io-client';
import { Server } from 'socket.io';
import { createApp } from '../app.js';
import { setupSocketGateway, resetSocketGatewayState } from '../gateway/socket.js';
import { initializePrisma } from '../utils/prisma.js';

describe('Part 1 Item 1: Student Media Modes, Mute All & Host Controls Integration Test', () => {
  const app = createApp();
  let server: http.Server;
  let serverPort: number;
  let teacherToken: string;
  let student1Token: string;
  let teacherSocket: Socket;
  let student1Socket: Socket;
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

    const teacherLogin = await request(app).post('/api/v1/auth/login').send({
      email: 'teacher1@apex.edu',
      password: 'Password@123',
    });
    teacherToken = teacherLogin.body.accessToken;

    const student1Login = await request(app).post('/api/v1/auth/login').send({
      email: 'student1@apex.edu',
      password: 'Password@123',
    });
    student1Token = student1Login.body.accessToken;

    teacherSocket = Client(`http://localhost:${serverPort}`, {
      auth: { token: teacherToken },
      transports: ['websocket'],
    });

    student1Socket = Client(`http://localhost:${serverPort}`, {
      auth: { token: student1Token },
      transports: ['websocket'],
    });

    await Promise.all([
      new Promise<void>((res) => teacherSocket.on('connect', () => res())),
      new Promise<void>((res) => student1Socket.on('connect', () => res())),
    ]);

    teacherSocket.emit('class:join', { classId: testClassId });
    student1Socket.emit('class:join', { classId: testClassId });
    await new Promise((r) => setTimeout(r, 150));
  });

  after(() => {
    teacherSocket?.disconnect();
    student1Socket?.disconnect();
    ioServer?.close();
    server?.close();
    resetSocketGatewayState();
  });

  it('1. Host emits media:mode:set (HAND_RAISE_ONLY) -> Student receives host:muted with isLocked=true', async () => {
    const studentMutedPromise = new Promise<{ isLocked: boolean }>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for host:muted')), 4000);
      student1Socket.on('host:muted', (data: any) => {
        clearTimeout(timer);
        resolve(data);
      });
    });

    teacherSocket.emit('media:mode:set', {
      classId: testClassId,
      mode: 'HAND_RAISE_ONLY',
    });

    const mutedData = await studentMutedPromise;
    assert.strictEqual(mutedData.isLocked, true, 'Student microphone must be locked in HAND_RAISE_ONLY mode');
  });

  it('2. Hand-Raise FIFO Queue: Student raises hand -> Host receives hand:queue updated with student in order', async () => {
    const hostHandPromise = new Promise<{ hands: any[] }>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for hand:queue')), 4000);
      teacherSocket.on('hand:queue', (data: any) => {
        clearTimeout(timer);
        resolve(data);
      });
    });

    student1Socket.emit('hand:raise', { classId: testClassId });

    const queueData = await hostHandPromise;
    assert.ok(Array.isArray(queueData.hands), 'hands must be an array');
    assert.ok(queueData.hands.length >= 1, 'At least one student in hand raise queue');
  });

  it('3. Host allows student to speak -> Student receives host:allowSpeak event to unlock mic', async () => {
    const allowSpeakPromise = new Promise<{ classId: string }>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for host:allowSpeak')), 4000);
      student1Socket.on('host:allowSpeak', (data: any) => {
        clearTimeout(timer);
        resolve(data);
      });
    });

    // Get student user id
    const meRes = await request(app)
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${student1Token}`);
    const studentId = meRes.body.user?.id || meRes.body.id;

    teacherSocket.emit('host:allowSpeak', {
      classId: testClassId,
      studentId,
    });

    const allowData = await allowSpeakPromise;
    assert.strictEqual(allowData.classId, testClassId);
  });
});
