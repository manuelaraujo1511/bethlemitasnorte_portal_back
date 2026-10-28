// Arnés de pruebas IDOR (S1.2). Regla del proyecto: un recurso fuera del alcance
// de quien pregunta responde 404, nunca 403, y es indistinguible de uno que no existe.
//
// Dos niveles, para engancharlos a cada endpoint nuevo (S2.1 en adelante):
//   1. Política: `expectHidden(actor, recursos)` llama a `authorize()` con todas las
//      acciones y exige AppError 404 `not_found`.
//   2. Ruta: `expectIdorRoute(...)` pide la URL de un recurso ajeno con cada actor y
//      compara la respuesta con la de un id que no existe: mismo estado, mismo
//      `application/problem+json`, mismo cuerpo (salvo `requestId`).
import { expect } from 'vitest';
import type { CoordinatorType, Role } from '../../src/db.js';
import { AppError } from '../../src/http/problem.js';
import { teacherGroupIds, type Actor, type ActorAssignment } from '../../src/modules/authz/actor.js';
import { authorize, type Action, type ObservationKind, type Resource } from '../../src/modules/authz/policy.js';

export const ALL_ACTIONS: readonly Action[] = ['create', 'read', 'update', 'delete', 'acknowledge'];

/** Estado HTTP con el que `authorize` corta, o 200 si deja pasar. */
export function statusOf(fn: () => void): number {
  try {
    fn();
    return 200;
  } catch (e) {
    if (e instanceof AppError) return e.status;
    throw e;
  }
}

/** El error exacto de `authorize`, o null si deja pasar. */
function errorOf(fn: () => void): AppError | null {
  try {
    fn();
    return null;
  } catch (e) {
    if (e instanceof AppError) return e;
    throw e;
  }
}

/**
 * Todas las acciones sobre cada recurso deben cortar con 404 `not_found`
 * (ni 200, ni 403: un 403 confirmaría que el recurso existe).
 */
export function expectHidden(label: string, actor: Actor, resources: readonly Resource[], actions: readonly Action[] = ALL_ACTIONS): void {
  for (const resource of resources) {
    for (const action of actions) {
      const err = errorOf(() => authorize(actor, action, resource));
      const where = `${label} / ${action} / ${JSON.stringify(resource)}`;
      expect(err, `${where}: debía responder 404 y dejó pasar`).not.toBeNull();
      expect({ status: err!.status, code: err!.code }, where).toEqual({ status: 404, code: 'not_found' });
    }
  }
}

// ---------------------------------------------------------------- Actores

export interface ActorInput extends Partial<Omit<Actor, 'roles' | 'coordinatorTypes'>> {
  roles: Role[];
  coordinatorTypes?: CoordinatorType[];
}

export function makeActor(over: ActorInput): Actor {
  return {
    userId: 0,
    schoolId: 1,
    staffId: null,
    assignments: new Map<number, ActorAssignment>(),
    directedGroupIds: new Set<number>(),
    enrollment: null,
    ...over,
    roles: new Set(over.roles),
    coordinatorTypes: new Set(over.coordinatorTypes ?? []),
  };
}

// ------------------------------------------------------------- Catálogo de recursos

/**
 * Una instancia de cada tipo de recurso en un colegio. `Record<Resource['type'], ...>`
 * hace fallar el typecheck si alguien agrega un tipo a `policy.ts` sin extender el arnés.
 */
export function oneOfEachType(schoolId: number, ids: { studentId: number; groupId: number; assignmentId: number; staffId: number; userId: number }): Resource[] {
  const { studentId, groupId, assignmentId, staffId, userId } = ids;
  const byType: Record<Resource['type'], Resource[]> = {
    school: [{ type: 'school', schoolId }],
    user: (['school_admin', 'coordinator', 'teacher', 'student'] as Role[]).map((role) => ({ type: 'user', schoolId, role })),
    user_contact: [{ type: 'user_contact', schoolId }],
    enrollment: [{ type: 'enrollment', schoolId, studentId, classGroupId: groupId }],
    staff: [{ type: 'staff', schoolId }],
    academic_structure: [{ type: 'academic_structure', schoolId }],
    teaching_assignment: [{ type: 'teaching_assignment', schoolId, staffId, classGroupId: groupId }],
    task_event: [{ type: 'task_event', schoolId, assignmentId, audienceGroupIds: [groupId] }],
    school_event: [
      { type: 'school_event', schoolId, audienceGroupIds: [groupId] },
      { type: 'school_event', schoolId, audienceGroupIds: [] },
    ],
    grade: [
      { type: 'grade', schoolId, assignmentId, studentId, published: true },
      { type: 'grade', schoolId, assignmentId, studentId, published: false },
    ],
    attendance: [{ type: 'attendance', schoolId, classGroupId: groupId, studentId }],
    observation: (['reconocimiento', 'convivencia', 'academica'] as ObservationKind[]).map((kind) => ({
      type: 'observation' as const,
      schoolId,
      kind,
      studentId,
      classGroupId: groupId,
    })),
    self_assessment: [{ type: 'self_assessment', schoolId, assignmentId, studentId, windowOpen: true }],
    // El actor figura como participante/creador/asignado: en otro colegio igual debe ser 404.
    message: [{ type: 'message', schoolId, participantUserIds: [userId] }],
    new_message: [{ type: 'new_message', schoolId, recipientUserIds: [userId] }],
    pqrs: [{ type: 'pqrs', schoolId, createdByUserId: userId, assignedToUserId: userId }],
    notice: [
      { type: 'notice', schoolId, audienceGroupIds: [groupId] },
      { type: 'notice', schoolId, audienceGroupIds: [] },
    ],
    sensitive: [{ type: 'sensitive', schoolId, studentId }],
    audit: [{ type: 'audit', schoolId }],
  };
  return Object.values(byType).flat();
}

/**
 * Recursos de OTRO colegio, de todos los tipos. Ninguno es accesible por un actor
 * del colegio 1, ni siquiera cuando su propio id figura como participante o creador.
 */
export function crossSchoolResources(foreignSchoolId: number, actorUserId: number): Resource[] {
  return oneOfEachType(foreignSchoolId, { studentId: 500, groupId: 50, assignmentId: 900, staffId: 90, userId: actorUserId });
}

export interface Peers {
  schoolId: number;
  /** Estudiantes distintos del propio (mismo colegio). */
  studentIds: readonly number[];
  /** Grupos fuera del alcance del actor. */
  groupIds: readonly number[];
  /** Asignaciones docentes que el actor no tiene. */
  assignmentIds: readonly number[];
  /** Personal distinto del propio. */
  staffIds: readonly number[];
  /** Otros usuarios (creadores de PQRS, participantes de mensajes). */
  otherUserIds: readonly number[];
}

/**
 * Recursos del mismo colegio que quedan fuera del alcance de un estudiante o un
 * docente: de otro estudiante, de otro grupo o de una asignación ajena.
 * Las coordinaciones y la administración ven todo el colegio: no aplican.
 */
export function peerResources(p: Peers): Resource[] {
  const { schoolId } = p;
  const out: Resource[] = [];
  for (const studentId of p.studentIds) {
    for (const groupId of p.groupIds) {
      out.push({ type: 'enrollment', schoolId, studentId, classGroupId: groupId });
      out.push({ type: 'attendance', schoolId, classGroupId: groupId, studentId });
      for (const kind of ['reconocimiento', 'convivencia', 'academica'] as const) {
        out.push({ type: 'observation', schoolId, kind, studentId, classGroupId: groupId });
      }
    }
    out.push({ type: 'sensitive', schoolId, studentId });
    for (const assignmentId of p.assignmentIds) {
      out.push({ type: 'grade', schoolId, assignmentId, studentId, published: true });
      out.push({ type: 'self_assessment', schoolId, assignmentId, studentId, windowOpen: true });
    }
  }
  for (const groupId of p.groupIds) {
    for (const staffId of p.staffIds) out.push({ type: 'teaching_assignment', schoolId, staffId, classGroupId: groupId });
    out.push({ type: 'school_event', schoolId, audienceGroupIds: [groupId] });
    out.push({ type: 'notice', schoolId, audienceGroupIds: [groupId] });
    for (const assignmentId of p.assignmentIds) out.push({ type: 'task_event', schoolId, assignmentId, audienceGroupIds: [groupId] });
  }
  for (const other of p.otherUserIds) {
    out.push({ type: 'message', schoolId, participantUserIds: [other] });
    out.push({ type: 'pqrs', schoolId, createdByUserId: other, assignedToUserId: other });
  }
  return out;
}

/**
 * Deriva los "ajenos" de un actor cargado (del seed o a mano) a partir de universos
 * conocidos: lo que el actor no tiene es lo ajeno. Sirve para estudiantes y docentes.
 */
export function peersOf(
  actor: Actor,
  universe: { schoolId: number; studentIds: readonly number[]; groupIds: readonly number[]; assignmentIds: readonly number[]; staffIds: readonly number[]; userIds: readonly number[] },
): Peers {
  const myGroups = actor.enrollment ? new Set([actor.enrollment.classGroupId]) : teacherGroupIds(actor);
  return {
    schoolId: universe.schoolId,
    studentIds: universe.studentIds.filter((id) => id !== actor.enrollment?.studentId),
    groupIds: universe.groupIds.filter((id) => !myGroups.has(id)),
    assignmentIds: universe.assignmentIds.filter((id) => !actor.assignments.has(id)),
    staffIds: universe.staffIds.filter((id) => id !== actor.staffId),
    otherUserIds: universe.userIds.filter((id) => id !== actor.userId),
  };
}

// ------------------------------------------------------------- Nivel ruta

/** Lo mínimo que el arnés necesita de una respuesta HTTP (compatible con `app.inject`). */
export interface IdorResponse {
  statusCode: number;
  headers: Record<string, unknown>;
  json(): unknown;
}

export interface IdorRouteCase {
  /** Para el mensaje de fallo: "estudiante pide la nota de otro estudiante". */
  label: string;
  /** Pide el recurso AJENO como este actor (el llamador sabe hacer login). */
  asActor: () => Promise<IdorResponse>;
}

function normalized(res: IdorResponse) {
  const rest = { ...(res.json() as Record<string, unknown>) };
  delete rest.requestId;
  return { status: res.statusCode, contentType: String(res.headers['content-type'] ?? '').split(';')[0], body: rest };
}

/**
 * Cada petición ajena debe responder 404 `application/problem+json` con el mismo
 * cuerpo que `missing` (el mismo endpoint con un id que no existe en ninguna parte).
 * Así ni el estado, ni el código, ni el texto delatan que el recurso existe.
 */
export async function expectIdorRoute(missing: () => Promise<IdorResponse>, cases: readonly IdorRouteCase[]): Promise<void> {
  const baseline = normalized(await missing());
  expect(baseline.status, 'la referencia (id inexistente) debe ser 404').toBe(404);
  expect(baseline.contentType).toBe('application/problem+json');
  for (const c of cases) {
    expect(normalized(await c.asActor()), c.label).toEqual(baseline);
  }
}
