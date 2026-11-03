// S1.2: pruebas IDOR. Actores como los del seed de desarrollo (db/seed_dev*.sql);
// la versión que los carga de MySQL está en test/db/idor.db.test.ts.
import type { FastifyPluginAsync, LightMyRequestResponse } from 'fastify';
import { beforeAll, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { AppError } from '../src/http/problem.js';
import { hashPassword } from '../src/modules/auth/crypto.js';
import { CSRF_COOKIE } from '../src/modules/auth/plugin.js';
import type { Actor, ActorStore } from '../src/modules/authz/actor.js';
import { authorize, can, requireActor } from '../src/modules/authz/policy.js';
import { memoryAuthStore, type MemoryUser } from './support/memory-auth-store.js';
import { crossSchoolResources, expectHidden, expectIdorRoute, makeActor, oneOfEachType, peerResources, peersOf, statusOf } from './support/idor.js';

const S = 1; // colegio demo
const OTHER = 2; // segundo colegio (sintético; el seed solo trae uno)
const G5 = 5; // 3.º A
const G6 = 6; // 3.º B

// Mismos ids que el seed: usuarios 2-9 docentes, 10-14 coordinación/admin, 15 Ana, 101-139 estudiantes.
const actors = {
  plataforma: makeActor({ userId: 1, schoolId: null, roles: ['platform_admin'] }),
  admin: makeActor({ userId: 14, staffId: 13, roles: ['school_admin'] }),
  coordAcad: makeActor({ userId: 10, staffId: 9, roles: ['coordinator', 'school_admin'], coordinatorTypes: ['academica'] }),
  coordConv: makeActor({ userId: 12, staffId: 11, roles: ['coordinator'], coordinatorTypes: ['convivencia'] }),
  coordOrient: makeActor({ userId: 13, staffId: 12, roles: ['coordinator'], coordinatorTypes: ['orientacion'] }),
  // luis.gomez: Matemáticas en 3.º B (1) y 3.º A (101).
  luis: makeActor({
    userId: 2,
    staffId: 1,
    roles: ['teacher'],
    assignments: new Map([
      [1, { classGroupId: G6, subjectId: 1, role: 'titular' }],
      [101, { classGroupId: G5, subjectId: 1, role: 'titular' }],
    ]),
  }),
  // Docente de 3.º B únicamente (Entorno social, asignación 5).
  docenteB: makeActor({ userId: 6, staffId: 5, roles: ['teacher'], assignments: new Map([[5, { classGroupId: G6, subjectId: 5, role: 'titular' }]]), directedGroupIds: new Set([G6]) }),
  // Directora de 3.º A sin clases vigentes hoy (su reemplazo en 3.º B venció).
  directoraA: makeActor({ userId: 3, staffId: 2, roles: ['teacher'], directedGroupIds: new Set([G5]) }),
  ana: makeActor({ userId: 15, roles: ['student'], enrollment: { id: 1, studentId: 1, classGroupId: G6 } }),
  est101: makeActor({ userId: 101, roles: ['student'], enrollment: { id: 101, studentId: 101, classGroupId: G6 } }),
  est130: makeActor({ userId: 130, roles: ['student'], enrollment: { id: 130, studentId: 130, classGroupId: G5 } }),
  sinMatricula: makeActor({ userId: 140, roles: ['student'] }),
} satisfies Record<string, Actor>;

const universe = {
  schoolId: S,
  studentIds: [1, 101, 130],
  groupIds: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  assignmentIds: [1, 2, 3, 4, 5, 6, 7, 8, 101, 102, 103, 104],
  staffIds: [1, 2, 3, 4, 5, 6, 7, 8],
  userIds: [2, 3, 4, 5, 6, 7, 8, 9, 15, 101, 130],
};

const inSchool = Object.entries(actors).filter(([n]) => n !== 'plataforma') as [string, Actor][];
const mine = { studentId: 1, groupId: G6, assignmentId: 1, staffId: 1 };

describe('otro colegio: 404 para todos, en todas las acciones', () => {
  it.each(inSchool)('%s', (name, actor) => {
    expectHidden(name, actor, crossSchoolResources(OTHER, actor.userId));
  });

  it('un actor del otro colegio tampoco entra en el colegio 1', () => {
    const adminOtro = makeActor({ userId: 90, schoolId: OTHER, roles: ['school_admin'] });
    expectHidden('adminOtro', adminOtro, oneOfEachType(S, { ...mine, userId: 90 }));
  });

  it('platform_admin: sin datos de menores en ningún colegio (nota 1)', () => {
    const minors = [S, OTHER].flatMap((school) =>
      oneOfEachType(school, { ...mine, userId: 1 }).filter((r) => !['school', 'audit'].includes(r.type) && !(r.type === 'user' && r.role === 'school_admin')),
    );
    expectHidden('plataforma', actors.plataforma, minors);
  });

  it('sin colegio en el host (schoolId null) un actor de colegio no alcanza nada', () => {
    expectHidden('sin host', makeActor({ userId: 14, schoolId: null, roles: ['school_admin'] }), oneOfEachType(S, { ...mine, userId: 14 }));
  });
});

describe('mismo colegio: otro estudiante, otro grupo, asignación ajena', () => {
  const scoped = Object.entries(actors).filter(([n]) => ['ana', 'est101', 'est130', 'luis', 'docenteB', 'directoraA'].includes(n)) as [string, Actor][];

  it.each(scoped)('%s no alcanza lo que queda fuera de su alcance', (name, actor) => {
    const resources = peerResources(peersOf(actor, universe));
    expect(resources.length, 'el universo debe generar casos').toBeGreaterThan(20);
    // Cada recurso lleva un grupo, una asignación o un estudiante ajenos al actor.
    expectHidden(name, actor, resources);
  });

  it('estudiante: compañero de su mismo grupo (nota publicada, asistencia, observación, autoevaluación)', () => {
    const mate = 101;
    expectHidden('ana', actors.ana, [
      { type: 'enrollment', schoolId: S, studentId: mate, classGroupId: G6 },
      { type: 'grade', schoolId: S, assignmentId: 1, studentId: mate, published: true },
      { type: 'attendance', schoolId: S, classGroupId: G6, studentId: mate },
      { type: 'observation', schoolId: S, kind: 'convivencia', studentId: mate, classGroupId: G6 },
      { type: 'self_assessment', schoolId: S, assignmentId: 1, studentId: mate, windowOpen: true },
      { type: 'sensitive', schoolId: S, studentId: mate },
    ]);
  });

  it('estudiante: la PQRS y el correo de otra persona', () => {
    expectHidden('ana', actors.ana, [
      { type: 'pqrs', schoolId: S, createdByUserId: 101, assignedToUserId: null },
      { type: 'message', schoolId: S, participantUserIds: [101, 2] },
    ]);
  });

  it('estudiante sin matrícula activa: nada del colegio', () => {
    const all = oneOfEachType(S, { ...mine, userId: 140 }).filter((r) => r.type !== 'message' && r.type !== 'new_message' && r.type !== 'user_contact');
    expectHidden('sinMatricula', actors.sinMatricula, all);
  });

  it('docente: PQRS no asignada a él y notas de asignaciones ajenas', () => {
    expectHidden('docenteB', actors.docenteB, [
      { type: 'pqrs', schoolId: S, createdByUserId: 15, assignedToUserId: 2 },
      { type: 'grade', schoolId: S, assignmentId: 1, studentId: 1, published: true },
      { type: 'grade', schoolId: S, assignmentId: 101, studentId: 130, published: true },
    ]);
  });

  it('un reemplazo vencido ya no alcanza la asignación', () => {
    // directoraA (elena.vargas) reemplazó Inglés de 3.º B (asignación 9) hasta el 09/10.
    expectHidden('directoraA', actors.directoraA, [
      { type: 'grade', schoolId: S, assignmentId: 9, studentId: 1, published: true },
      { type: 'task_event', schoolId: S, assignmentId: 9, audienceGroupIds: [G6] },
    ]);
  });
});

describe('authorize distingue 404 de 403', () => {
  it('lo que no puede ver: 404 con cualquier acción, sin pista de que existe', () => {
    const r = { type: 'grade', schoolId: S, assignmentId: 1, studentId: 1, published: true } as const;
    for (const action of ['create', 'read', 'update', 'delete', 'acknowledge'] as const) {
      expect(statusOf(() => authorize(actors.est101, action, r))).toBe(404);
    }
  });

  it('lo que ve pero no puede hacer: 403', () => {
    const own = { type: 'grade', schoolId: S, assignmentId: 1, studentId: 1, published: true } as const;
    expect(statusOf(() => authorize(actors.ana, 'read', own))).toBe(200);
    expect(statusOf(() => authorize(actors.ana, 'update', own))).toBe(403);
    expect(statusOf(() => authorize(actors.ana, 'delete', own))).toBe(403);
  });

  it('nota sin publicar: para el estudiante no existe (404, no 403)', () => {
    const r = { type: 'grade', schoolId: S, assignmentId: 1, studentId: 1, published: false } as const;
    expect(statusOf(() => authorize(actors.ana, 'read', r))).toBe(404);
  });

  it('el 404 de authorize es idéntico al de un recurso inexistente', () => {
    let err: unknown;
    try {
      authorize(actors.est101, 'read', { type: 'enrollment', schoolId: S, studentId: 1, classGroupId: G6 });
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(AppError);
    expect(err).toMatchObject({ status: 404, code: 'not_found', title: 'No existe' });
  });

  it('un actor con permiso no recibe error (control positivo)', () => {
    expect(can(actors.ana, 'read', { type: 'enrollment', schoolId: S, studentId: 1, classGroupId: G6 })).toBe(true);
    expect(() => authorize(actors.luis, 'update', { type: 'grade', schoolId: S, assignmentId: 1, studentId: 1, published: false })).not.toThrow();
  });
});

// ---------------------------------------------------------------- Arnés de ruta

const HOST = 'demo.campus.localhost';
const PASSWORD = 'una frase larga de prueba';
const school = { id: S, publicId: '00000000-0000-4000-8000-000000000001', code: 'demo', name: 'Demo', timezone: 'America/Bogota', host: HOST };
let hash: string;
beforeAll(async () => {
  hash = await hashPassword(PASSWORD);
});

function user(id: number): MemoryUser {
  const username = `u${id}`;
  return {
    id,
    username,
    passwordHash: hash,
    me: { id: `00000000-0000-4000-8000-${String(id).padStart(12, '0')}`, username, displayName: username, firstName: username, lastName: 'Prueba', email: null, roles: [{ role: 'student', coordinatorType: null }] },
  };
}

const bySession: Record<number, Actor> = { 15: actors.ana, 101: actors.est101, 130: actors.est130, 2: actors.luis, 6: actors.docenteB };
const actorStore: ActorStore = {
  async loadActor(userId) {
    return bySession[userId] ?? null;
  },
};

function build(apiModules: FastifyPluginAsync[]) {
  const mem = memoryAuthStore([school], Object.keys(bySession).map((id) => user(Number(id))));
  return buildApp({
    config: { LOG_LEVEL: 'silent' },
    checkDb: async () => {},
    auth: { store: mem.store, actors: actorStore, secret: 'x'.repeat(40), idleMs: 1_800_000, maxMs: 43_200_000 },
    apiModules,
  });
}

/** Inicia sesión como `u<id>` y devuelve un GET con sus cookies. */
async function as(app: ReturnType<typeof build>, id: number) {
  const jar = new Map<string, string>();
  const keep = (res: LightMyRequestResponse) => {
    for (const c of res.cookies as { name: string; value: string; maxAge?: number }[]) {
      if (c.value === '' || c.maxAge === 0) jar.delete(c.name);
      else jar.set(c.name, c.value);
    }
  };
  const cookie = () => [...jar].map(([k, v]) => `${k}=${v}`).join('; ');
  keep(await app.inject({ method: 'GET', url: '/api/v1/auth/csrf', headers: { host: HOST } }));
  const login = await app.inject({
    method: 'POST',
    url: '/api/v1/auth/login',
    headers: { host: HOST, cookie: cookie(), 'x-csrf-token': jar.get(CSRF_COOKIE) ?? '' },
    payload: { username: `u${id}`, password: PASSWORD },
  });
  expect(login.statusCode, `login u${id}`).toBe(200);
  keep(login);
  return (url: string) => app.inject({ method: 'GET', url, headers: { host: HOST, cookie: cookie() } });
}

describe('arnés de ruta (expectIdorRoute) con un endpoint de muestra', () => {
  // GET /grades/:id como lo escribirá S2.1: un id inexistente y uno ajeno terminan en el mismo 404.
  const grades = new Map([[7, { id: 7, schoolId: S, assignmentId: 1, studentId: 1, published: true }]]);
  const gradesRoute: FastifyPluginAsync = async (api) => {
    api.get<{ Params: { id: string } }>('/grades/:id', async (request) => {
      const actor = requireActor(request);
      const g = grades.get(Number(request.params.id));
      if (!g) throw new AppError(404, 'not_found', 'No existe');
      authorize(actor, 'read', { type: 'grade', schoolId: g.schoolId, assignmentId: g.assignmentId, studentId: g.studentId, published: g.published });
      return { id: g.id };
    });
  };

  it('el dueño lo lee (control positivo)', async () => {
    const get = await as(build([gradesRoute]), 15);
    expect((await get('/api/v1/grades/7')).statusCode).toBe(200);
  });

  it('otro estudiante y un docente de otra asignación reciben el mismo 404 que un id inexistente', async () => {
    const app = build([gradesRoute]);
    const owner = await as(app, 15);
    const peer = await as(app, 101);
    const otherGroup = await as(app, 130);
    const teacherB = await as(app, 6);
    await expectIdorRoute(() => owner('/api/v1/grades/99999'), [
      { label: 'compañero del mismo grupo', asActor: () => peer('/api/v1/grades/7') },
      { label: 'estudiante de otro grupo', asActor: () => otherGroup('/api/v1/grades/7') },
      { label: 'docente de otra asignación', asActor: () => teacherB('/api/v1/grades/7') },
    ]);
  });

  it('el arnés detecta un endpoint que filtra con 403', async () => {
    const leaky: FastifyPluginAsync = async (api) => {
      api.get('/leaky/:id', async (request) => {
        requireActor(request);
        throw new AppError(403, 'forbidden', 'No tienes permiso para esto');
      });
    };
    const get = await as(build([leaky]), 101);
    await expect(expectIdorRoute(() => get('/api/v1/no-existe'), [{ label: 'fuga', asActor: () => get('/api/v1/leaky/1') }])).rejects.toThrow();
  });
});
