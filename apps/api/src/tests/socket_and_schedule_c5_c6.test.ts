import { describe, it, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import request from 'supertest';
import { io as Client, Socket } from 'socket.io-client';
import { Server } from 'socket.io';
import { createApp } from '../app.js';
import { setupSocketGateway, resetSocketGatewayState } from '../gateway/socket.js';
import { initializePrisma, prisma } from '../utils/prisma.js';

describe('Phase C — C5 Socket Chat (2 Clients) & C6 Multi-Batch Schedule Suite', () => {
  const app = createApp();
  let server: http.Server;
  let serverPort: number;
  let teacherToken: string;
  let student1Token: string;
  let teacherSocket: Socket;
  let studentSocket: Socket;
  let ioServer: Server;

  before(async () => {
    await initializePrisma();

    // Start real HTTP & Socket.IO server on dynamic port
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

    // Ensure Physics and Maths classes and slots exist for C5 & C6 tests
    const institute = await prisma.institute.findFirst({ where: { slug: 'apex-academy' } });
    const teacher = await prisma.user.findFirst({ where: { email: 'teacher1@apex.edu' } });
    const student = await prisma.user.findFirst({ where: { email: 'student1@apex.edu' } });

    if (institute && teacher && student) {
      await prisma.batch.upsert({
        where: { id: 'batch-jee-phy' },
        create: {
          id: 'batch-jee-phy',
          instituteId: institute.id,
          teacherId: teacher.id,
          name: 'Class 12 JEE — Physics',
          subject: 'Physics',
          joinCode: 'JEEPHY',
        },
        update: { teacherId: teacher.id },
      });

      await prisma.batch.upsert({
        where: { id: 'batch-jee-mth' },
        create: {
          id: 'batch-jee-mth',
          instituteId: institute.id,
          teacherId: teacher.id,
          name: 'Class 12 JEE — Maths',
          subject: 'Mathematics',
          joinCode: 'JEEMTH',
        },
        update: { teacherId: teacher.id },
      });

      await prisma.enrollment.upsert({
        where: { instituteId_batchId_studentId: { instituteId: institute.id, batchId: 'batch-jee-phy', studentId: student.id } },
        create: { instituteId: institute.id, batchId: 'batch-jee-phy', studentId: student.id, status: 'ACTIVE' },
        update: { status: 'ACTIVE' },
      });
      await prisma.enrollment.upsert({
        where: { instituteId_batchId_studentId: { instituteId: institute.id, batchId: 'batch-jee-mth', studentId: student.id } },
        create: { instituteId: institute.id, batchId: 'batch-jee-mth', studentId: student.id, status: 'ACTIVE' },
        update: { status: 'ACTIVE' },
      });

      const now = new Date();
      await prisma.liveClass.upsert({
        where: { id: 'class-demo-phy-01' },
        create: {
          id: 'class-demo-phy-01',
          instituteId: institute.id,
          batchId: 'batch-jee-phy',
          teacherId: teacher.id,
          title: 'Electromagnetic Induction & Faraday’s Laws',
          scheduledAt: new Date(now.getTime() + 2 * 3600000),
          status: 'SCHEDULED',
          livekitRoom: 'room-jee-phy-01',
        },
        update: { status: 'SCHEDULED', teacherId: teacher.id },
      });

      await prisma.liveClass.upsert({
        where: { id: 'class-demo-mth-01' },
        create: {
          id: 'class-demo-mth-01',
          instituteId: institute.id,
          batchId: 'batch-jee-mth',
          teacherId: teacher.id,
          title: 'Calculus: Integration by Parts & Definite Integrals',
          scheduledAt: new Date(now.getTime() + 4 * 3600000),
          status: 'SCHEDULED',
          livekitRoom: 'room-jee-mth-01',
        },
        update: { status: 'SCHEDULED', teacherId: teacher.id },
      });

      const existingPhySlot = await prisma.timetableSlot.findFirst({
        where: { batchId: 'batch-jee-phy', dayOfWeek: 1 },
      });
      if (!existingPhySlot) {
        await prisma.timetableSlot.create({
          data: {
            instituteId: institute.id,
            teacherId: teacher.id,
            batchId: 'batch-jee-phy',
            dayOfWeek: 1,
            startMin: 540,
            endMin: 600,
            recurring: true,
          },
        });
      }

      const existingMthSlot = await prisma.timetableSlot.findFirst({
        where: { batchId: 'batch-jee-mth', dayOfWeek: 1 },
      });
      if (!existingMthSlot) {
        await prisma.timetableSlot.create({
          data: {
            instituteId: institute.id,
            teacherId: teacher.id,
            batchId: 'batch-jee-mth',
            dayOfWeek: 1,
            startMin: 630,
            endMin: 690,
            recurring: true,
          },
        });
      }
    }

    // Login Teacher (Prof. Rajesh Sharma)
    const teacherLogin = await request(app).post('/api/v1/auth/login').send({
      email: 'teacher1@apex.edu',
      password: 'Password@123',
    });
    teacherToken = teacherLogin.body.accessToken;

    // Login Student 1 (Aarav Patel - Enrolled in Physics and Maths)
    const studentLogin = await request(app).post('/api/v1/auth/login').send({
      email: 'student1@apex.edu',
      password: 'Password@123',
    });
    student1Token = studentLogin.body.accessToken;
  });

  /* -------------------------------------------------------------------------- */
  /* C5: SOCKET TWO-CLIENT REALTIME CHAT & HISTORY PERSISTENCE                  */
  /* -------------------------------------------------------------------------- */
  it('C5: Two socket clients join classroom, exchange messages, and verify history', async () => {
    const serverUrl = `http://localhost:${serverPort}`;
    const testClassId = 'class-demo-phy-01';

    const waitForConnect = (sock: Socket): Promise<void> => {
      return new Promise((resolve, reject) => {
        if (sock.connected) return resolve();
        sock.once('connect', () => resolve());
        sock.once('connect_error', (err) => reject(err));
        setTimeout(() => reject(new Error('Socket connection timed out')), 4000);
      });
    };

    try {
      // 1. Connect Teacher Socket
      teacherSocket = Client(serverUrl, {
        auth: { token: teacherToken },
        transports: ['polling', 'websocket'],
        reconnection: false,
      });

      // 2. Connect Student Socket
      studentSocket = Client(serverUrl, {
        auth: { token: student1Token },
        transports: ['polling', 'websocket'],
        reconnection: false,
      });

      await Promise.all([
        waitForConnect(teacherSocket),
        waitForConnect(studentSocket),
      ]);

      // 3. Both join classroom and wait for room acknowledgment
      const teacherJoined = new Promise((resolve) => teacherSocket.once('chat:history', resolve));
      const studentJoined = new Promise((resolve) => studentSocket.once('chat:history', resolve));

      teacherSocket.emit('class:join', { classId: testClassId });
      studentSocket.emit('class:join', { classId: testClassId });

      await Promise.all([teacherJoined, studentJoined]);

      // 4. Teacher sends chat message -> Student receives it
      const studentReceivedMsgPromise = new Promise<any>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('Student chat receive timeout')), 4000);
        studentSocket.on('chat:message', (data) => {
          if (data.text === 'Welcome students to Quantum Physics') {
            clearTimeout(timer);
            resolve(data);
          }
        });
      });

      teacherSocket.emit('chat:send', {
        classId: testClassId,
        text: 'Welcome students to Quantum Physics',
      });

      const receivedByStudent = await studentReceivedMsgPromise;
      assert.equal(receivedByStudent.text, 'Welcome students to Quantum Physics');
      assert.equal(receivedByStudent.senderRole, 'TEACHER');

      // 5. Student replies -> Teacher receives it
      const teacherReceivedMsgPromise = new Promise<any>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('Teacher chat receive timeout')), 4000);
        teacherSocket.on('chat:message', (data) => {
          if (data.text === 'Good morning Sir, audio is clear!') {
            clearTimeout(timer);
            resolve(data);
          }
        });
      });

      studentSocket.emit('chat:send', {
        classId: testClassId,
        text: 'Good morning Sir, audio is clear!',
      });

      const receivedByTeacher = await teacherReceivedMsgPromise;
      assert.equal(receivedByTeacher.text, 'Good morning Sir, audio is clear!');
      assert.equal(receivedByTeacher.senderRole, 'STUDENT');

      // 6. Connect third client to verify chat:history persistence (last 50 messages)
      const thirdSocket = Client(serverUrl, {
        auth: { token: student1Token },
        transports: ['polling', 'websocket'],
        reconnection: false,
      });

      const historyPromise = new Promise<any[]>((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error('History receive timeout')), 4000);
        thirdSocket.on('chat:history', (data) => {
          clearTimeout(timer);
          resolve(data.messages);
        });
      });

      await waitForConnect(thirdSocket);
      thirdSocket.emit('class:join', { classId: testClassId });
      const history = await historyPromise;
      thirdSocket.close();

      assert.ok(history.length >= 2, 'History must contain at least 2 messages');
      const texts = history.map((m) => m.text);
      assert.ok(texts.includes('Welcome students to Quantum Physics'));
      assert.ok(texts.includes('Good morning Sir, audio is clear!'));
    } catch (err: any) {
      console.error('*** C5 ERROR ***:', err.message, err.stack);
      throw err;
    }
  });

  /* -------------------------------------------------------------------------- */
  /* C6: MULTI-BATCH STUDENT SCHEDULE AND REALTIME CREATION UPDATES             */
  /* -------------------------------------------------------------------------- */
  it('C6: Student enrolled in 2 batches (Physics + Maths) sees classes and slots from both', async () => {
    // Ensure both Physics and Maths classes exist at test time
    const now = new Date();
    await prisma.liveClass.upsert({
      where: { id: 'class-demo-mth-01' },
      create: {
        id: 'class-demo-mth-01',
        instituteId: 'inst-apex-01',
        batchId: 'batch-jee-mth',
        teacherId: 'usr-teacher-01',
        title: 'Calculus: Integration by Parts & Definite Integrals',
        scheduledAt: new Date(now.getTime() + 4 * 3600000),
        status: 'SCHEDULED',
        livekitRoom: 'room-jee-mth-01',
      },
      update: { status: 'SCHEDULED', teacherId: 'usr-teacher-01' },
    });

    // 1. Student queries /api/v1/classes without filter -> Sees both today classes (Physics & Maths)
    const classesRes = await request(app)
      .get('/api/v1/classes')
      .set('Authorization', `Bearer ${student1Token}`);

    assert.equal(classesRes.status, 200);
    const classes = classesRes.body.classes;
    assert.ok(Array.isArray(classes), 'Classes must be an array');
    const subjects = classes.map((c: any) => c.batch?.subject);
    assert.ok(subjects.includes('Physics'), 'Student must see Physics class');
    assert.ok(subjects.some((s: string) => s && s.toLowerCase().includes('math')), 'Student must see Mathematics class');

    // 2. Student queries /api/v1/timetable -> Sees slots for both Physics and Maths on Monday (day 1)
    await prisma.timetableSlot.upsert({
      where: { id: 'slot-demo-phy-mon' },
      create: {
        id: 'slot-demo-phy-mon',
        instituteId: 'inst-apex-01',
        teacherId: 'usr-teacher-01',
        batchId: 'batch-jee-phy',
        dayOfWeek: 1,
        startMin: 540,
        endMin: 600,
        recurring: true,
      },
      update: {},
    });
    await prisma.timetableSlot.upsert({
      where: { id: 'slot-demo-mth-mon' },
      create: {
        id: 'slot-demo-mth-mon',
        instituteId: 'inst-apex-01',
        teacherId: 'usr-teacher-01',
        batchId: 'batch-jee-mth',
        dayOfWeek: 1,
        startMin: 630,
        endMin: 690,
        recurring: true,
      },
      update: {},
    });

    const slotsRes = await request(app)
      .get('/api/v1/timetable?dayOfWeek=1')
      .set('Authorization', `Bearer ${student1Token}`);

    assert.equal(slotsRes.status, 200);
    const slots = slotsRes.body.slots;
    const slotSubjects = slots.map((s: any) => s.batch?.subject);
    assert.ok(slotSubjects.includes('Physics'), 'Student must see Physics slot on Monday');
    assert.ok(slotSubjects.some((s: string) => s && s.toLowerCase().includes('math')), 'Student must see Mathematics slot on Monday');

    // 3. Teacher creates a new class in Physics -> Student receives realtime socket event 'class:scheduled'
    if (!studentSocket || !studentSocket.connected) {
      studentSocket = Client(`http://localhost:${serverPort}`, {
        auth: { token: student1Token },
        transports: ['polling', 'websocket'],
        reconnection: false,
      });
      await new Promise<void>((resolve) => {
        if (studentSocket.connected) return resolve();
        studentSocket.once('connect', () => resolve());
      });
    }

    const studentScheduledPromise = new Promise<any>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('Realtime class:scheduled timeout')), 6000);
      studentSocket.on('class:scheduled', (data) => {
        clearTimeout(timer);
        resolve(data);
      });
    });

    const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const createClassRes = await request(app)
      .post('/api/v1/classes')
      .set('Authorization', `Bearer ${teacherToken}`)
      .send({
        batchId: 'batch-jee-phy',
        title: 'Wave Optics: Youngs Double Slit Experiment',
        scheduledAt: tomorrow,
      });

    assert.equal(createClassRes.status, 201);
    const createdClassId = createClassRes.body.id;

    const scheduledEvent = await studentScheduledPromise;
    assert.equal(scheduledEvent.classId, createdClassId);
    assert.ok(scheduledEvent.title.includes('Wave Optics'));

    // 4. Verify student's classes list now contains the newly scheduled class
    const updatedClassesRes = await request(app)
      .get('/api/v1/classes')
      .set('Authorization', `Bearer ${student1Token}`);

    assert.equal(updatedClassesRes.status, 200);
    const foundNewClass = updatedClassesRes.body.classes.find((c: any) => c.id === createdClassId);
    assert.ok(foundNewClass, 'Student must see newly scheduled class in classes list');
  });

  after(async () => {
    resetSocketGatewayState();
    if (teacherSocket) teacherSocket.disconnect();
    if (studentSocket) studentSocket.disconnect();
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
    const handles = (process as any)._getActiveHandles?.() || [];
    for (const h of handles) {
      if (h !== process.stdout && h !== process.stderr && h !== process.stdin) {
        if (typeof h?.destroy === 'function') {
          try { h.destroy(); } catch {}
        } else if (typeof h?.unref === 'function') {
          try { h.unref(); } catch {}
        }
      }
    }
  });
});
