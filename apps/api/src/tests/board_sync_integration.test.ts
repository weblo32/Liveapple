import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import request from 'supertest';
import { io as Client, Socket } from 'socket.io-client';
import { Server } from 'socket.io';
import { createApp } from '../app.js';
import { setupSocketGateway, resetSocketGatewayState } from '../gateway/socket.js';
import { initializePrisma, prisma } from '../utils/prisma.js';

describe('BUG B — Whiteboard Stage, Realtime Strokes & Late Joiner Snapshot Test', () => {
  const app = createApp();
  let server: http.Server;
  let serverPort: number;
  let teacherToken: string;
  let student1Token: string;
  let student2Token: string;
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

    // Login Teacher
    const teacherLogin = await request(app).post('/api/v1/auth/login').send({
      email: 'teacher1@apex.edu',
      password: 'Password@123',
    });
    teacherToken = teacherLogin.body.accessToken;

    // Login Student 1
    const student1Login = await request(app).post('/api/v1/auth/login').send({
      email: 'student1@apex.edu',
      password: 'Password@123',
    });
    student1Token = student1Login.body.accessToken;

    // Login Student 2
    const student2Login = await request(app).post('/api/v1/auth/login').send({
      email: 'student2@apex.edu',
      password: 'Password@123',
    });
    student2Token = student2Login.body.accessToken;

    // Connect Teacher Socket
    teacherSocket = Client(`http://localhost:${serverPort}`, {
      auth: { token: teacherToken },
      transports: ['websocket'],
    });

    // Connect Student 1 Socket
    student1Socket = Client(`http://localhost:${serverPort}`, {
      auth: { token: student1Token },
      transports: ['websocket'],
    });

    await Promise.all([
      new Promise<void>((res) => teacherSocket.on('connect', () => res())),
      new Promise<void>((res) => student1Socket.on('connect', () => res())),
    ]);

    // Both join classroom room
    teacherSocket.emit('class:join', { classId: testClassId });
    student1Socket.emit('class:join', { classId: testClassId });

    await new Promise((r) => setTimeout(r, 200));
  });

  it('Teacher presses Board -> broadcasts stage:state and stage:changed (BOARD), student receives BOARD', async () => {
    const studentStagePromise = new Promise<{ stage: string; mode: string }>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for stage:state')), 3000);
      student1Socket.once('stage:state', (data: any) => {
        clearTimeout(timer);
        resolve(data);
      });
    });

    const studentBoardPromise = new Promise<{ isOpen: boolean }>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for board:state')), 3000);
      student1Socket.once('board:state', (data: any) => {
        clearTimeout(timer);
        resolve(data);
      });
    });

    // Teacher opens board by emitting stage:set and board:toggle
    teacherSocket.emit('stage:set', { classId: testClassId, stage: 'BOARD', mode: 'BOARD' });

    const [stageEvent, boardEvent] = await Promise.all([studentStagePromise, studentBoardPromise]);
    assert.equal(stageEvent.stage, 'BOARD');
    assert.equal(stageEvent.mode, 'BOARD');
    assert.equal(boardEvent.isOpen, true);
  });

  it('Teacher draws stroke -> stroke arrives on student canvas', async () => {
    const testStroke = {
      color: '#3B82F6',
      width: 4,
      points: [{ x: 50, y: 100 }, { x: 75, y: 150 }],
    };

    const strokePromise = new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for whiteboard:draw')), 3000);
      student1Socket.once('whiteboard:draw', (stroke: any) => {
        clearTimeout(timer);
        resolve(stroke);
      });
    });

    teacherSocket.emit('whiteboard:draw', { classId: testClassId, stroke: testStroke });

    const receivedStroke = await strokePromise;
    assert.equal(receivedStroke.color, '#3B82F6');
    assert.equal(receivedStroke.points.length, 2);
  });

  it('Late joiner connects and receives classroom:snapshot with BOARD stage, strokes and view-only permissions', async () => {
    const student2Socket = Client(`http://localhost:${serverPort}`, {
      auth: { token: student2Token },
      transports: ['websocket'],
    });

    await new Promise<void>((res) => student2Socket.on('connect', () => res()));

    const snapshotPromise = new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for classroom:snapshot')), 3000);
      student2Socket.once('classroom:snapshot', (snapshot: any) => {
        clearTimeout(timer);
        resolve(snapshot);
      });
    });

    student2Socket.emit('class:join', { classId: testClassId });

    const snapshot = await snapshotPromise;
    assert.equal(snapshot.stage, 'BOARD');
    assert.equal(snapshot.mode, 'BOARD');
    assert.equal(snapshot.board.isOpen, true);
    assert.equal(snapshot.board.canDraw, false); // Student must be view-only!
    assert.ok(Array.isArray(snapshot.board.strokes));
    assert.ok(snapshot.board.strokes.length >= 1, 'Late joiner must get existing strokes from snapshot');

    student2Socket.disconnect();
  });

  it('Closing the board returns everyone to VIDEO stage', async () => {
    const studentReturnPromise = new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for return to VIDEO')), 3000);
      student1Socket.once('stage:state', (data: any) => {
        clearTimeout(timer);
        resolve(data);
      });
    });

    teacherSocket.emit('board:toggle', { classId: testClassId, isOpen: false });

    const returnEvent = await studentReturnPromise;
    assert.equal(returnEvent.stage, 'VIDEO');
  });

  after(async () => {
    resetSocketGatewayState();
    if (teacherSocket) teacherSocket.disconnect();
    if (student1Socket) student1Socket.disconnect();
    if (ioServer) {
      ioServer.disconnectSockets(true);
      await new Promise<void>((r) => ioServer.close(() => r()));
    }
    if (server && server.listening) {
      if (typeof (server as any).closeAllConnections === 'function') {
        (server as any).closeAllConnections();
      }
      await new Promise<void>((r) => server.close(() => r()));
    }
  });
});
