import { describe, expect, it } from 'vitest';
import type { CoordinatorType, Role } from '../src/db.js';
import { AppError } from '../src/http/problem.js';
import type { Actor, ActorAssignment } from '../src/modules/authz/actor.js';
import { authorize, can, type Action, type Resource } from '../src/modules/authz/policy.js';

// Colegio 1, grupo 6 (3.º B) y grupo 5 (3.º A). Estudiante 1 está en el grupo 6.
const S = 1;
const OTHER = 2;
const G6 = 6;
const G5 = 5;
const STUDENT = 1;
const OTHER_STUDENT = 2;

type ActorInput = Partial<Omit<Actor, 'roles' | 'coordinatorTypes'>> & { roles: Role[]; coordinatorTypes?: CoordinatorType[] };

function actor(over: ActorInput): Actor {
  return {
    userId: 0,
    schoolId: S,
    staffId: null,
    assignments: new Map(),
    directedGroupIds: new Set(),
    enrollment: null,
    ...over,
    roles: new Set(over.roles),
    coordinatorTypes: new Set(over.coordinatorTypes ?? []),
  };
}
const asg = (entries: [number, ActorAssignment][]) => new Map(entries);

const actors = {
  plataforma: actor({ userId: 1, schoolId: null, roles: ['platform_admin'] }),
  admin: actor({ userId: 14, staffId: 13, roles: ['school_admin'] }),
  adminOtro: actor({ userId: 90, schoolId: OTHER, roles: ['school_admin'] }),
  coordAcad: actor({ userId: 10, staffId: 9, roles: ['coordinator'], coordinatorTypes: ['academica'] }),
  coordConv: actor({ userId: 12, staffId: 11, roles: ['coordinator'], coordinatorTypes: ['convivencia'] }),
  coordOrient: actor({ userId: 13, staffId: 12, roles: ['coordinator'], coordinatorTypes: ['orientacion'] }),
  // Titular de Matemáticas (asignación 1) en 3.º B.
  titular: actor({ userId: 2, staffId: 1, roles: ['teacher'], assignments: asg([[1, { classGroupId: G6, subjectId: 1, role: 'titular' }]]) }),
  // Reemplazo vigente de Inglés (asignación 9) en 3.º B.
  reemplazo: actor({ userId: 3, staffId: 2, roles: ['teacher'], assignments: asg([[9, { classGroupId: G6, subjectId: 3, role: 'reemplazo' }]]) }),
  // Docente sin asignaciones en 3.º B, pero director de ese grupo.
  director: actor({ userId: 6, staffId: 5, roles: ['teacher'], directedGroupIds: new Set([G6]) }),
  // Docente solo de 3.º A.
  docenteOtroGrupo: actor({ userId: 4, staffId: 3, roles: ['teacher'], assignments: asg([[103, { classGroupId: G5, subjectId: 3, role: 'titular' }]]) }),
  estudiante: actor({ userId: 15, roles: ['student'], enrollment: { id: 1, studentId: STUDENT, classGroupId: G6 } }),
  otroEstudiante: actor({ userId: 101, roles: ['student'], enrollment: { id: 2, studentId: OTHER_STUDENT, classGroupId: G5 } }),
  estudianteSinMatricula: actor({ userId: 140, roles: ['student'] }),
} satisfies Record<string, Actor>;
type Name = keyof typeof actors;

const letters: Record<string, Action> = { C: 'create', R: 'read', U: 'update', D: 'delete', A: 'acknowledge' };
const allActions: Action[] = ['create', 'read', 'update', 'delete', 'acknowledge'];

/** Cada actor que no aparece no puede nada sobre el recurso. */
function matrix(resource: Resource, expected: Partial<Record<Name, string>>) {
  for (const [name, a] of Object.entries(actors) as [Name, Actor][]) {
    const want = new Set([...(expected[name] ?? '')].map((l) => letters[l]));
    const got = allActions.filter((act) => can(a, act, resource));
    expect(new Set(got), `${resource.type} / ${name}`).toEqual(want);
  }
}

describe('matriz de permisos (database-design.md §2)', () => {
  it('colegios', () => {
    matrix({ type: 'school', schoolId: S }, { plataforma: 'CRU', admin: 'R' });
  });

  it('usuarios y roles', () => {
    matrix(
      { type: 'user', schoolId: S, role: 'teacher' },
      { admin: 'CRUD', coordAcad: 'R', coordConv: 'R', coordOrient: 'R', titular: 'R', reemplazo: 'R', director: 'R', docenteOtroGrupo: 'R', estudiante: 'R', otroEstudiante: 'R' },
    );
    // El admin de plataforma solo maneja cuentas de admin de colegio.
    expect(can(actors.plataforma, 'create', { type: 'user', schoolId: S, role: 'school_admin' })).toBe(true);
    expect(can(actors.plataforma, 'delete', { type: 'user', schoolId: S, role: 'school_admin' })).toBe(false);
    // Nadie de un colegio toca una cuenta de plataforma.
    expect(can(actors.admin, 'update', { type: 'user', schoolId: S, role: 'platform_admin' })).toBe(false);
  });

  it('matrículas', () => {
    matrix(
      { type: 'enrollment', schoolId: S, studentId: STUDENT, classGroupId: G6 },
      { admin: 'CRU', coordAcad: 'R', coordConv: 'R', coordOrient: 'R', titular: 'R', reemplazo: 'R', director: 'R', estudiante: 'R' },
    );
  });

  it('docentes y estructura académica', () => {
    const everyone = { coordAcad: 'R', coordConv: 'R', coordOrient: 'R', titular: 'R', reemplazo: 'R', director: 'R', docenteOtroGrupo: 'R', estudiante: 'R', otroEstudiante: 'R' };
    matrix({ type: 'staff', schoolId: S }, { admin: 'CRUD', ...everyone });
    matrix({ type: 'academic_structure', schoolId: S }, { admin: 'CRUD', ...everyone });
  });

  it('asignaciones docentes', () => {
    matrix(
      { type: 'teaching_assignment', schoolId: S, staffId: 1, classGroupId: G6 },
      { admin: 'CRUD', coordAcad: 'R', coordConv: 'R', coordOrient: 'R', titular: 'R', estudiante: 'R' },
    );
  });

  it('eventos tipo tarea', () => {
    matrix(
      { type: 'task_event', schoolId: S, assignmentId: 1, audienceGroupIds: [G6] },
      { admin: 'CRUD', coordAcad: 'CRUD', coordConv: 'CRUD', coordOrient: 'CRUD', titular: 'CRUD', estudiante: 'R' },
    );
  });

  it('eventos del colegio', () => {
    const coords = { admin: 'CRUD', coordAcad: 'CRUD', coordConv: 'CRUD', coordOrient: 'CRUD' };
    matrix(
      { type: 'school_event', schoolId: S, audienceGroupIds: [G6] },
      { ...coords, titular: 'CRU', reemplazo: 'CRU', director: 'CRU', estudiante: 'R' },
    );
    // Para todo el colegio: lo ven todos, solo admin y coordinación lo manejan.
    matrix(
      { type: 'school_event', schoolId: S, audienceGroupIds: [] },
      { ...coords, titular: 'R', reemplazo: 'R', director: 'R', docenteOtroGrupo: 'R', estudiante: 'R', otroEstudiante: 'R' },
    );
    // Un docente no crea un evento que incluye grupos ajenos.
    expect(can(actors.titular, 'create', { type: 'school_event', schoolId: S, audienceGroupIds: [G6, G5] })).toBe(false);
  });

  it('notas', () => {
    const base = { admin: 'RU', coordAcad: 'R', coordConv: 'R', coordOrient: 'R' };
    matrix({ type: 'grade', schoolId: S, assignmentId: 1, studentId: STUDENT, published: true }, { ...base, titular: 'CRU', estudiante: 'R' });
    matrix({ type: 'grade', schoolId: S, assignmentId: 1, studentId: STUDENT, published: false }, { ...base, titular: 'CRU' });
    // Solo el titular califica: el reemplazo ve, no escribe.
    matrix({ type: 'grade', schoolId: S, assignmentId: 9, studentId: STUDENT, published: false }, { ...base, reemplazo: 'R' });
  });

  it('asistencia', () => {
    matrix(
      { type: 'attendance', schoolId: S, classGroupId: G6, studentId: STUDENT },
      { admin: 'R', coordAcad: 'R', coordConv: 'R', coordOrient: 'R', titular: 'CRU', reemplazo: 'CRU', director: 'CRU', estudiante: 'R' },
    );
  });

  it('observador', () => {
    const teachers = { titular: 'CR', reemplazo: 'CR', director: 'CR', estudiante: 'RA' };
    matrix(
      { type: 'observation', schoolId: S, kind: 'convivencia', studentId: STUDENT, classGroupId: G6 },
      { admin: 'R', coordAcad: 'R', coordConv: 'CRU', coordOrient: 'R', ...teachers },
    );
    matrix(
      { type: 'observation', schoolId: S, kind: 'academica', studentId: STUDENT, classGroupId: G6 },
      { admin: 'R', coordAcad: 'CRU', coordConv: 'R', coordOrient: 'R', ...teachers },
    );
    matrix(
      { type: 'observation', schoolId: S, kind: 'reconocimiento', studentId: STUDENT, classGroupId: G6 },
      { admin: 'R', coordAcad: 'CRU', coordConv: 'CRU', coordOrient: 'CRU', ...teachers },
    );
  });

  it('autoevaluación', () => {
    const base = { admin: 'R', coordAcad: 'R', titular: 'CR' };
    matrix({ type: 'self_assessment', schoolId: S, assignmentId: 1, studentId: STUDENT, windowOpen: true }, { ...base, estudiante: 'CRU' });
    matrix({ type: 'self_assessment', schoolId: S, assignmentId: 1, studentId: STUDENT, windowOpen: false }, { ...base, estudiante: 'R' });
  });

  it('correo: lo leen sus participantes', () => {
    matrix(
      { type: 'message', schoolId: S, participantUserIds: [2, 15] },
      {
        admin: 'CR', coordAcad: 'CR', coordConv: 'CR', coordOrient: 'CR',
        titular: 'CR', reemplazo: 'C', director: 'C', docenteOtroGrupo: 'C', estudiante: 'CR', otroEstudiante: 'C',
      },
    );
  });

  it('PQRS', () => {
    matrix(
      { type: 'pqrs', schoolId: S, createdByUserId: 15, assignedToUserId: 2 },
      { admin: 'RU', coordAcad: 'RU', coordConv: 'RU', coordOrient: 'RU', titular: 'R', estudiante: 'CR' },
    );
  });

  it('avisos y documentos', () => {
    const coords = { admin: 'CRUD', coordAcad: 'CRUD', coordConv: 'CRUD', coordOrient: 'CRUD' };
    matrix({ type: 'notice', schoolId: S, audienceGroupIds: [G6] }, { ...coords, titular: 'CRUD', reemplazo: 'CRUD', director: 'CRUD', estudiante: 'R' });
    matrix(
      { type: 'notice', schoolId: S, audienceGroupIds: [] },
      { ...coords, titular: 'R', reemplazo: 'R', director: 'R', docenteOtroGrupo: 'R', estudiante: 'R', otroEstudiante: 'R' },
    );
  });

  it('salud y documento de identidad', () => {
    matrix({ type: 'sensitive', schoolId: S, studentId: STUDENT }, { admin: 'RU', coordOrient: 'R', estudiante: 'R' });
  });

  it('auditoría', () => {
    matrix({ type: 'audit', schoolId: S }, { plataforma: 'R', admin: 'R' });
  });
});

describe('aislamiento entre colegios', () => {
  const samples: Resource[] = [
    { type: 'school', schoolId: OTHER },
    { type: 'enrollment', schoolId: OTHER, studentId: STUDENT, classGroupId: G6 },
    { type: 'grade', schoolId: OTHER, assignmentId: 1, studentId: STUDENT, published: true },
    { type: 'notice', schoolId: OTHER, audienceGroupIds: [] },
    { type: 'sensitive', schoolId: OTHER, studentId: STUDENT },
  ];

  it('nadie de un colegio ve nada de otro, aunque coincidan los ids', () => {
    for (const r of samples) {
      for (const name of ['admin', 'coordAcad', 'titular', 'estudiante'] as const) {
        for (const act of allActions) expect(can(actors[name], act, r), `${name} ${act} ${r.type}`).toBe(false);
      }
    }
    expect(can(actors.adminOtro, 'read', { type: 'school', schoolId: OTHER })).toBe(true);
  });

  it('el admin de plataforma no ve datos de menores', () => {
    for (const r of samples.slice(1)) expect(can(actors.plataforma, 'read', r), r.type).toBe(false);
  });

  it('un estudiante sin matrícula activa no ve nada', () => {
    expect(can(actors.estudianteSinMatricula, 'read', { type: 'notice', schoolId: S, audienceGroupIds: [] })).toBe(false);
  });
});

describe('roles acumulados', () => {
  it('coordinadora académica y administradora suma ambos permisos', () => {
    const rosa = actor({ userId: 10, staffId: 9, roles: ['coordinator', 'school_admin'], coordinatorTypes: ['academica'] });
    expect(can(rosa, 'create', { type: 'enrollment', schoolId: S, studentId: STUDENT, classGroupId: G6 })).toBe(true);
    expect(can(rosa, 'update', { type: 'observation', schoolId: S, kind: 'academica', studentId: STUDENT, classGroupId: G6 })).toBe(true);
    expect(can(rosa, 'update', { type: 'observation', schoolId: S, kind: 'convivencia', studentId: STUDENT, classGroupId: G6 })).toBe(false);
  });
});

describe('authorize', () => {
  const grade: Resource = { type: 'grade', schoolId: S, assignmentId: 9, studentId: STUDENT, published: false };

  it('404 si no lo puede ver, 403 si lo ve pero no puede hacerlo', () => {
    const status = (fn: () => void) => {
      try {
        fn();
        return 200;
      } catch (err) {
        return (err as AppError).status;
      }
    };
    expect(status(() => authorize(actors.reemplazo, 'read', grade))).toBe(200);
    expect(status(() => authorize(actors.reemplazo, 'update', grade))).toBe(403);
    expect(status(() => authorize(actors.estudiante, 'read', grade))).toBe(404);
    expect(status(() => authorize(actors.docenteOtroGrupo, 'update', grade))).toBe(404);
  });
});
