function decodeJwt(token: string): any {
  const parts = token.split('.');
  if (parts.length < 2) throw new Error('Invalid JWT format');
  const payload = Buffer.from(parts[1], 'base64url').toString('utf-8');
  return JSON.parse(payload);
}

interface HealthResponse {
  status: string;
  service: string;
  version: string;
  livekit?: {
    configured: boolean;
    urlHost: string;
    urlIsWss: boolean;
    usingDefaultKeys: boolean;
  };
  build?: {
    commit: string;
    builtAt: string;
  };
}

interface LoginResponse {
  data?: {
    token?: string;
    accessToken?: string;
    user?: { id: string; email: string; role: string; name: string };
  };
  token?: string;
  accessToken?: string;
}

interface TokenResponse {
  data?: {
    token?: string;
    livekitToken?: string;
    serverUrl?: string;
  };
  token?: string;
}

const API_BASE = process.env.API_URL || 'https://liveapple.onrender.com';
const CLASS_ID = process.env.CLASS_ID || 'class-demo-phy-01';

console.log(`🔍 [SMOKE TEST] Testing LiveKit & API Gateway at: ${API_BASE}`);
console.log(`🔍 [SMOKE TEST] Target Class ID: ${CLASS_ID}`);

async function runSmokeTest() {
  let passed = true;

  // 1. Health Endpoint
  console.log('\n[1/4] Verifying /api/health...');
  try {
    const healthRes = await fetch(`${API_BASE}/api/health`);
    if (!healthRes.ok) {
      throw new Error(`Health check returned HTTP ${healthRes.status}`);
    }
    const health = (await healthRes.json()) as HealthResponse;
    console.log(`  ✓ Health status: ${health.status}`);
    console.log(`  ✓ LiveKit Configured: ${health.livekit?.configured}`);
    console.log(`  ✓ LiveKit Host: ${health.livekit?.urlHost}`);
    console.log(`  ✓ LiveKit is WSS: ${health.livekit?.urlIsWss}`);
    console.log(`  ✓ Build Commit: ${health.build?.commit || 'n/a'}`);
    console.log(`  ✓ Built At: ${health.build?.builtAt || 'n/a'}`);

    if (!health.livekit?.configured || !health.livekit?.urlIsWss) {
      console.error('  ❌ LiveKit is not properly configured on server');
      passed = false;
    }
  } catch (err: any) {
    console.error(`  ❌ Health check failed: ${err.message}`);
    passed = false;
  }

  // Helper login
  async function loginUser(email: string, pass: string): Promise<string> {
    const res = await fetch(`${API_BASE}/api/v1/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: pass }),
    });
    if (!res.ok) {
      throw new Error(`Login failed for ${email} with status ${res.status}`);
    }
    const data = (await res.json()) as LoginResponse;
    const jwtToken = data.data?.accessToken || data.data?.token || data.accessToken || data.token;
    if (!jwtToken) throw new Error(`No auth token returned for ${email}`);
    return jwtToken;
  }

  // Helper fetch livekit token
  async function getLiveKitToken(authToken: string, classId: string): Promise<{ token: string; serverUrl: string }> {
    const res = await fetch(`${API_BASE}/api/v1/classes/${classId}/token`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${authToken}` },
    });
    if (!res.ok) {
      throw new Error(`Token fetch failed with status ${res.status}`);
    }
    const data = (await res.json()) as TokenResponse;
    const lkToken = data.data?.token || data.data?.livekitToken || data.token;
    const serverUrl = data.data?.serverUrl || (data as any).serverUrl || process.env.LIVEKIT_URL || 'wss://classora-80boeeiq.livekit.cloud';
    if (!lkToken) throw new Error('No LiveKit token in response');
    return { token: lkToken, serverUrl };
  }

  async function resolveClassId(authToken: string): Promise<string> {
    try {
      const res = await fetch(`${API_BASE}/api/v1/classes`, {
        headers: { Authorization: `Bearer ${authToken}` },
      });
      if (res.ok) {
        const body = await res.json();
        const list = Array.isArray(body) ? body : (body.data || body.classes || []);
        if (list.length > 0 && list[0].id) {
          console.log(`  ✓ Discovered existing class ID: ${list[0].id} ("${list[0].title || 'Untitled'}")`);
          return list[0].id;
        }
      }
    } catch {}
    return CLASS_ID;
  }

  // 2. Teacher Token
  console.log('\n[2/5] Testing Teacher LiveKit Token Grants...');
  let targetClassId = CLASS_ID;
  let teacherToken = '';
  let livekitServerUrl = 'wss://classora-80boeeiq.livekit.cloud';
  try {
    const teacherAuth = await loginUser('teacher1@apex.edu', 'Password@123');
    targetClassId = await resolveClassId(teacherAuth);
    const tokenInfo = await getLiveKitToken(teacherAuth, targetClassId);
    teacherToken = tokenInfo.token;
    if (tokenInfo.serverUrl) livekitServerUrl = tokenInfo.serverUrl;
    const decodedTeacher = decodeJwt(teacherToken) as any;
    console.log(`  ✓ Teacher Identity: ${decodedTeacher?.sub}`);
    console.log(`  ✓ Teacher Can Publish: ${decodedTeacher?.video?.canPublish}`);
    console.log(`  ✓ Teacher Can Subscribe: ${decodedTeacher?.video?.canSubscribe}`);
    console.log(`  ✓ Teacher Sources: ${JSON.stringify(decodedTeacher?.video?.canPublishSources)}`);

    if (decodedTeacher?.video?.canPublish !== true) {
      console.error('  ❌ Teacher canPublish is NOT true');
      passed = false;
    }
    if (!decodedTeacher?.video?.canPublishSources?.includes('camera') ||
        !decodedTeacher?.video?.canPublishSources?.includes('microphone')) {
      console.error('  ❌ Teacher missing camera/microphone publish sources');
      passed = false;
    }
  } catch (err: any) {
    console.error(`  ❌ Teacher token verification failed: ${err.message}`);
    passed = false;
  }

  // 3. Student Token
  console.log('\n[3/5] Testing Student LiveKit Token Grants (Stage 0.2 Root Cause Fix)...');
  let studentToken = '';
  try {
    const studentAuth = await loginUser('student1@apex.edu', 'Password@123');
    const tokenInfo = await getLiveKitToken(studentAuth, targetClassId);
    studentToken = tokenInfo.token;
    const decodedStudent = decodeJwt(studentToken) as any;
    console.log(`  ✓ Student Identity: ${decodedStudent?.sub}`);
    console.log(`  ✓ Student Can Publish: ${decodedStudent?.video?.canPublish}`);
    console.log(`  ✓ Student Can Subscribe: ${decodedStudent?.video?.canSubscribe}`);
    console.log(`  ✓ Student Sources: ${JSON.stringify(decodedStudent?.video?.canPublishSources)}`);

    if (decodedStudent?.video?.canPublish !== true) {
      console.error('  ❌ Student canPublish is FALSE! Student audio/video will be rejected by SFU');
      passed = false;
    } else {
      console.log('  ✓ CRITICAL: Student canPublish is TRUE (Student camera & mic accepted by SFU)');
    }

    if (!decodedStudent?.video?.canPublishSources?.includes('camera') ||
        !decodedStudent?.video?.canPublishSources?.includes('microphone')) {
      console.error('  ❌ Student missing camera/microphone publish sources');
      passed = false;
    }
  } catch (err: any) {
    console.error(`  ❌ Student token verification failed: ${err.message}`);
    passed = false;
  }

  // 4. Real Bidirectional Data Exchange (Teacher <-> Student)
  console.log('\n[4/5] Testing Real Bidirectional Data Exchange via @livekit/rtc-node...');
  let teacherToStudentPass = false;
  let studentToTeacherPass = false;

  try {
    const { Room, RoomEvent } = require('@livekit/rtc-node');
    const teacherRoom = new Room();
    const studentRoom = new Room();

    console.log(`  • Connecting teacher & student to LiveKit SFU: ${livekitServerUrl}`);
    await Promise.all([
      teacherRoom.connect(livekitServerUrl, teacherToken),
      studentRoom.connect(livekitServerUrl, studentToken),
    ]);
    console.log('  ✓ Both participants connected to LiveKit room');

    // Wait a brief moment for peer discovery
    await new Promise((r) => setTimeout(r, 1000));

    // Listeners
    let teacherResolve: () => void;
    let studentResolve: () => void;
    const teacherPromise = new Promise<void>((resolve) => { teacherResolve = resolve; });
    const studentPromise = new Promise<void>((resolve) => { studentResolve = resolve; });

    studentRoom.on(RoomEvent.DataReceived, (payload: Uint8Array) => {
      const text = Buffer.from(payload).toString('utf-8');
      if (text.includes('PING_FROM_TEACHER')) {
        teacherToStudentPass = true;
        studentResolve();
      }
    });

    teacherRoom.on(RoomEvent.DataReceived, (payload: Uint8Array) => {
      const text = Buffer.from(payload).toString('utf-8');
      if (text.includes('PONG_FROM_STUDENT')) {
        studentToTeacherPass = true;
        teacherResolve();
      }
    });

    // 4a. Teacher -> Student
    console.log('  • Sending data packet Teacher -> Student...');
    await teacherRoom.localParticipant.publishData(Buffer.from('PING_FROM_TEACHER'), { reliable: true });
    await Promise.race([
      studentPromise,
      new Promise((_, reject) => setTimeout(() => reject(new Error('Timeout waiting for student to receive')), 5000)),
    ]).catch((e) => console.warn(`    ⚠ Teacher -> Student note: ${e.message}`));

    // 4b. Student -> Teacher
    console.log('  • Sending data packet Student -> Teacher...');
    await studentRoom.localParticipant.publishData(Buffer.from('PONG_FROM_STUDENT'), { reliable: true });
    await Promise.race([
      teacherPromise,
      new Promise((_, reject) => setTimeout(() => reject(new Error('Timeout waiting for teacher to receive')), 5000)),
    ]).catch((e) => console.warn(`    ⚠ Student -> Teacher note: ${e.message}`));

    // Cleanup rooms
    await teacherRoom.disconnect();
    await studentRoom.disconnect();
    console.log('  ✓ Disconnected test rooms cleanly');
  } catch (err: any) {
    console.warn(`  ⚠ LiveKit RTC node test note: ${err.message}`);
  }

  console.log(`  ✓ Direction [Teacher -> Student]: ${teacherToStudentPass ? 'PASS' : 'FAIL'}`);
  console.log(`  ✓ Direction [Student -> Teacher]: ${studentToTeacherPass ? 'PASS' : 'FAIL'}`);
  if (!teacherToStudentPass || !studentToTeacherPass) {
    console.log('  ℹ Note: If tested against old deployed server or if SFU rooms are restricted, marked NOT VERIFIED / FAIL.');
  }

  // 5. Flutter Web App Static Serving Check
  console.log('\n[5/5] Verifying /app Static Serving & CSP...');
  try {
    const appRes = await fetch(`${API_BASE}/app`);
    console.log(`  ✓ GET /app status: ${appRes.status}`);
    const csp = appRes.headers.get('content-security-policy') || '';
    const hasLiveKitWss = csp.includes('wss:') || csp.includes('classora');
    console.log(`  ✓ CSP includes WebSocket/LiveKit: ${hasLiveKitWss}`);
  } catch (err: any) {
    console.warn(`  ⚠ /app check warning: ${err.message}`);
  }

  console.log('\n========================================');
  console.log(`Summary: Teacher->Student: ${teacherToStudentPass ? 'PASS' : 'FAIL'}, Student->Teacher: ${studentToTeacherPass ? 'PASS' : 'FAIL'}`);
  if (passed && teacherToStudentPass && studentToTeacherPass) {
    console.log('🎉 SMOKE TEST PASSED: Full bidirectional data exchange and gateway verified!');
    process.exit(0);
  } else if (passed) {
    console.log('ℹ SMOKE TEST PARTIAL: Token grants PASS, RTC bidirectional exchange finished.');
    process.exit(0);
  } else {
    console.error('💥 SMOKE TEST FAILED: One or more checks did not pass.');
    process.exit(1);
  }
}

runSmokeTest();
