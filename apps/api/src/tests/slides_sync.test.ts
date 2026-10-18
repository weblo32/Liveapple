import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import request from 'supertest';
import { io as Client, Socket } from 'socket.io-client';
import { Server } from 'socket.io';
import { createApp } from '../app.js';
import { setupSocketGateway, resetSocketGatewayState } from '../gateway/socket.js';
import { initializePrisma, prisma } from '../utils/prisma.js';

function createMockPdf(pageCount: number, title: string): Buffer {
  let content = `%PDF-1.4\n%âãÏÓ\n`;
  content += `1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n`;
  content += `2 0 obj\n<< /Type /Pages /Kids [`;
  for (let i = 0; i < pageCount; i++) {
    content += `${3 + i} 0 R `;
  }
  content += `] /Count ${pageCount} >>\nendobj\n`;
  for (let i = 0; i < pageCount; i++) {
    content += `${3 + i} 0 obj\n<< /Type /Page /Parent 2 0 R >>\nendobj\n`;
  }
  content += `trailer\n<< /Size ${3 + pageCount} /Root 1 0 R >>\nstartxref\n500\n%%EOF\n`;
  return Buffer.from(content);
}

describe('Part 1 Item 2 & Part 4: PDF Slides Upload & Real-Time Sync Integration Test', () => {
  const app = createApp();
  let server: http.Server;
  let serverPort: number;
  let teacherToken: string;
  let student1Token: string;
  let student2Token: string;
  let student4Token: string;
  let teacherSocket: Socket;
  let student1Socket: Socket;
  let student2Socket: Socket;
  let ioServer: Server;
  let testClassId = 'class-demo-phy-01';
  let deck1Id = '';
  let deck2Id = '';

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

    // 1. Teacher login (Apex institute)
    const teacherLogin = await request(app).post('/api/v1/auth/login').send({
      email: 'teacher1@apex.edu',
      password: 'Password@123',
    });
    teacherToken = teacherLogin.body.accessToken;

    const classesRes = await request(app)
      .get('/api/v1/classes')
      .set('Authorization', `Bearer ${teacherToken}`);
    const classList = Array.isArray(classesRes.body) ? classesRes.body : (classesRes.body?.data || classesRes.body?.classes || []);
    if (classList.length > 0 && classList[0].id) {
      testClassId = classList[0].id;
    }

    // 2. Enrolled student login (Apex institute)
    const student1Login = await request(app).post('/api/v1/auth/login').send({
      email: 'student1@apex.edu',
      password: 'Password@123',
    });
    student1Token = student1Login.body.accessToken;

    // 3. Late joiner student login (Apex institute)
    const student2Login = await request(app).post('/api/v1/auth/login').send({
      email: 'student2@apex.edu',
      password: 'Password@123',
    });
    student2Token = student2Login.body.accessToken;

    // 4. Student of another batch (Apex institute - Chemistry batch, NOT Physics)
    const otherBatchStudentLogin = await request(app).post('/api/v1/auth/login').send({
      email: 'student4@apex.edu',
      password: 'Password@123',
    });
    student4Token = otherBatchStudentLogin.body.accessToken;

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
    student2Socket?.disconnect();
    ioServer?.close();
    server?.close();
    resetSocketGatewayState();
  });

  it('1. Upload Validation: Rejects PPT/PPTX file with exact prompt message', async () => {
    const fakePpt = Buffer.from('Fake PPT Presentation Content');
    const res = await request(app)
      .post(`/api/v1/classes/${testClassId}/slides`)
      .set('Authorization', `Bearer ${teacherToken}`)
      .attach('file', fakePpt, 'lecture.pptx');

    assert.strictEqual(res.status, 400);
    assert.strictEqual(res.body.message, 'PPT ko PDF me export karo ya screen share karo');
  });

  it('2. Upload Validation: Rejects oversized file (> 50MB)', async () => {
    // 51MB buffer check
    const bigBuffer = Buffer.alloc(51 * 1024 * 1024, 'A');
    const res = await request(app)
      .post(`/api/v1/classes/${testClassId}/slides`)
      .set('Authorization', `Bearer ${teacherToken}`)
      .attach('file', bigBuffer, 'too_big.pdf');

    // Multer rejects with 400 or 500 when limit exceeded
    assert.ok(res.status === 400 || res.status === 500);
  });

  it('3. Upload PDF 1: 2-page Satyam_Pandey_Resume.pdf parses totalPages=2 and stores in DB', async () => {
    const pdf2Pages = createMockPdf(2, 'Satyam_Pandey_Resume');
    const res = await request(app)
      .post(`/api/v1/classes/${testClassId}/slides`)
      .set('Authorization', `Bearer ${teacherToken}`)
      .attach('file', pdf2Pages, 'Satyam_Pandey_Resume.pdf');

    assert.strictEqual(res.status, 201);
    assert.strictEqual(res.body.success, true);
    assert.strictEqual(res.body.fileName, 'Satyam_Pandey_Resume.pdf');
    assert.strictEqual(res.body.totalPages, 2, 'Must calculate exact 2 pages');
    assert.ok(res.body.deckId, 'Must return deckId');
    assert.ok(res.body.fileHash, 'Must return SHA-256 hash');
    assert.ok(res.body.url, 'Must return URL for student fetch');
    deck1Id = res.body.deckId;

    // Verify stored in DB ByteA column
    const inDb = await prisma.classSlideDeck.findUnique({ where: { id: deck1Id } });
    assert.ok(inDb, 'Slide deck must be persisted in ClassSlideDeck table');
    assert.strictEqual(inDb.totalPages, 2);
  });

  it('4. Upload PDF 2: 5-page Physics_Lecture.pdf parses totalPages=5 and stores in DB', async () => {
    const pdf5Pages = createMockPdf(5, 'Physics_Lecture');
    const res = await request(app)
      .post(`/api/v1/classes/${testClassId}/slides`)
      .set('Authorization', `Bearer ${teacherToken}`)
      .attach('file', pdf5Pages, 'Physics_Lecture.pdf');

    assert.strictEqual(res.status, 201);
    assert.strictEqual(res.body.success, true);
    assert.strictEqual(res.body.fileName, 'Physics_Lecture.pdf');
    assert.strictEqual(res.body.totalPages, 5, 'Must calculate exact 5 pages');
    assert.ok(res.body.deckId);
    deck2Id = res.body.deckId;
  });

  it('5. Enrolled Student Fetch: student1 can download deck 1 with valid auth', async () => {
    const res = await request(app)
      .get(`/api/v1/classes/${testClassId}/slides/${deck1Id}`)
      .set('Authorization', `Bearer ${student1Token}`);

    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.header['content-type'], 'application/pdf');
    assert.strictEqual(res.header['x-slide-total-pages'], '2');
    assert.ok(res.body.length > 0 || res.text.length > 0);
  });

  it('6. Authorization Security: Student of another batch cannot access class slides (403 Forbidden)', async () => {
    const res = await request(app)
      .get(`/api/v1/classes/${testClassId}/slides/${deck1Id}`)
      .set('Authorization', `Bearer ${student4Token}`);

    assert.strictEqual(res.status, 403, 'Must refuse access from non-enrolled batch student with 403');
    assert.strictEqual(res.body.message, 'Student is not enrolled in this batch');
  });

  it('7. Socket Sync: Teacher broadcasts doc:present and page change -> Student receives real-time sync', async () => {
    const studentDocPromise = new Promise<{ isOpen: boolean; page: number; title: string; totalPages: number; url: string }>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for doc:present')), 4000);
      student1Socket.on('doc:present', (data: any) => {
        clearTimeout(timer);
        resolve(data);
      });
    });

    // Teacher presents slide
    teacherSocket.emit('doc:present', {
      classId: testClassId,
      deckId: deck1Id,
      isOpen: true,
      title: 'Satyam_Pandey_Resume.pdf',
      fileName: 'Satyam_Pandey_Resume.pdf',
      page: 1,
      currentPage: 1,
      totalPages: 2,
      url: `/api/v1/classes/${testClassId}/slides/${deck1Id}`,
    });

    const docState = await studentDocPromise;
    assert.strictEqual(docState.isOpen, true);
    assert.strictEqual(docState.title, 'Satyam_Pandey_Resume.pdf');
    assert.strictEqual(docState.page, 1);
    assert.strictEqual(docState.totalPages, 2, 'Student receives correct totalPages=2');
    assert.ok(docState.url, 'Student receives deck download URL');

    // Teacher changes to page 2
    const studentPagePromise = new Promise<{ page: number }>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for doc:page')), 4000);
      student1Socket.on('doc:page', (data: any) => {
        clearTimeout(timer);
        resolve(data);
      });
    });

    teacherSocket.emit('doc:page', {
      classId: testClassId,
      page: 2,
      currentPage: 2,
    });

    const pageState = await studentPagePromise;
    assert.strictEqual(pageState.page, 2);
  });

  it('8. Late Joiner Snapshot: Student 2 joining later immediately receives stage SLIDES on current page 2 with totalPages=2', async () => {
    student2Socket = Client(`http://localhost:${serverPort}`, {
      auth: { token: student2Token },
      transports: ['websocket'],
    });

    await new Promise<void>((res) => student2Socket.on('connect', () => res()));

    const snapshotPromise = new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Timeout waiting for classroom:snapshot')), 4000);
      student2Socket.on('classroom:snapshot', (data: any) => {
        clearTimeout(timer);
        resolve(data);
      });
    });

    student2Socket.emit('class:join', { classId: testClassId });

    const snapshot = await snapshotPromise;
    assert.strictEqual(snapshot.stage, 'SLIDES', 'Stage in snapshot must be SLIDES');
    assert.ok(snapshot.doc, 'Snapshot must contain doc state');
    assert.strictEqual(snapshot.doc.isOpen, true);
    assert.strictEqual(snapshot.doc.page, 2, 'Late joiner must land on current page 2');
    assert.strictEqual(snapshot.doc.totalPages, 2, 'Late joiner receives totalPages=2');
    assert.strictEqual(snapshot.doc.title, 'Satyam_Pandey_Resume.pdf');
  });
});
