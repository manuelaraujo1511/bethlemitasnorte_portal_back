import type { Role } from '../../db.js';
import { AppError } from '../../http/problem.js';
import { teacherGroupIds, type Actor } from './actor.js';

/**
 * Política central de permisos: la matriz de docs/database-design.md §2 del repo
 * del portal. Cada ruta arma el recurso con lo que leyó de la base y pregunta
 * `can`; nada más decide permisos. Lo que no está permitido aquí está prohibido.
 */
export type Action = 'create' | 'read' | 'update' | 'delete' | 'acknowledge';

export type ObservationKind = 'reconocimiento' | 'convivencia' | 'academica';

export type Resource =
  | { type: 'school'; schoolId: number }
  /** Cuenta de usuario; `role` es el rol de la cuenta (el admin de plataforma solo maneja school_admin). */
  | { type: 'user'; schoolId: number; role: Role }
  | { type: 'enrollment'; schoolId: number; studentId: number; classGroupId: number }
  | { type: 'staff'; schoolId: number }
  /** Años, períodos, grados, grupos, materias y plan de estudios. */
  | { type: 'academic_structure'; schoolId: number }
  | { type: 'teaching_assignment'; schoolId: number; staffId: number; classGroupId: number }
  /** Evento de una materia (tarea, quiz...). `audienceGroupIds` = grupos que lo ven. */
  | { type: 'task_event'; schoolId: number; assignmentId: number; audienceGroupIds: readonly number[] }
  /** Evento del colegio (muestra, reunión, receso). Audiencia vacía = todo el colegio. */
  | { type: 'school_event'; schoolId: number; audienceGroupIds: readonly number[] }
  | { type: 'grade'; schoolId: number; assignmentId: number; studentId: number; published: boolean }
  | { type: 'attendance'; schoolId: number; classGroupId: number; studentId: number }
  | { type: 'observation'; schoolId: number; kind: ObservationKind; studentId: number; classGroupId: number }
  | { type: 'self_assessment'; schoolId: number; assignmentId: number; studentId: number; windowOpen: boolean }
  /** Un mensaje: lo leen sus participantes. Quién puede escribirle a quién lo valida el módulo de correo. */
  | { type: 'message'; schoolId: number; participantUserIds: readonly number[] }
  | { type: 'pqrs'; schoolId: number; createdByUserId: number; assignedToUserId: number | null }
  /** Aviso o documento. Audiencia vacía = todo el colegio. */
  | { type: 'notice'; schoolId: number; audienceGroupIds: readonly number[] }
  /** Salud y documento de identidad de un estudiante. */
  | { type: 'sensitive'; schoolId: number; studentId: number }
  /** audit_log; schoolId null = eventos de la plataforma. */
  | { type: 'audit'; schoolId: number | null };

type Crud = ReadonlySet<Action>;
const set = (...a: Action[]): Crud => new Set(a);
const NONE = set();
const R = set('read');
const CR = set('create', 'read');
const CRU = set('create', 'read', 'update');
const CRUD = set('create', 'read', 'update', 'delete');
const RU = set('read', 'update');

/** Todos los ids están en el conjunto (y hay al menos uno). */
const allIn = (ids: readonly number[], allowed: ReadonlySet<number>) => ids.length > 0 && ids.every((id) => allowed.has(id));
const anyIn = (ids: readonly number[], allowed: ReadonlySet<number>) => ids.some((id) => allowed.has(id));
/** Audiencia que incluye a quien tiene esos grupos (vacía = todo el colegio). */
const reaches = (audience: readonly number[], groups: ReadonlySet<number>) => audience.length === 0 || anyIn(audience, groups);

/** Tipo de coordinación que gestiona cada tipo de observación. */
const OBSERVATION_COORDINATOR: Record<ObservationKind, 'academica' | 'convivencia' | null> = {
  academica: 'academica',
  convivencia: 'convivencia',
  reconocimiento: null, // cualquier coordinación
};

export function can(actor: Actor, action: Action, resource: Resource): boolean {
  return allowed(actor, resource).has(action);
}

function allowed(actor: Actor, r: Resource): Crud {
  const { roles } = actor;

  // Plataforma: solo colegios, cuentas de admin de colegio y auditoría (Nota 1: sin datos de menores).
  if (roles.has('platform_admin')) {
    if (r.type === 'school') return CRU;
    if (r.type === 'user' && r.role === 'school_admin') return CRU;
    if (r.type === 'audit') return R;
    return NONE;
  }

  // Todo lo demás es de un colegio: el del host, nunca otro.
  if (actor.schoolId === null || r.schoolId !== actor.schoolId) return NONE;

  // Una persona puede acumular roles: vale la unión.
  const result = new Set<Action>();
  for (const role of roles) for (const a of byRole(actor, role, r)) result.add(a);
  return result;
}

function byRole(actor: Actor, role: Role, r: Resource): Crud {
  switch (role) {
    case 'platform_admin':
      return NONE;
    case 'school_admin':
      return schoolAdmin(r);
    case 'coordinator':
      return coordinator(actor, r);
    case 'teacher':
      return teacher(actor, r);
    case 'student':
      return student(actor, r);
  }
}

function schoolAdmin(r: Resource): Crud {
  switch (r.type) {
    case 'school':
      return R;
    case 'user':
      return r.role === 'platform_admin' ? NONE : CRUD;
    case 'enrollment':
      return CRU;
    case 'staff':
    case 'academic_structure':
    case 'teaching_assignment':
    case 'task_event':
    case 'school_event':
    case 'notice':
      return CRUD;
    case 'grade':
      return RU; // correcciones auditadas (B1.6)
    case 'attendance':
    case 'observation':
    case 'self_assessment':
    case 'audit':
      return R;
    case 'message':
      return CR;
    case 'pqrs':
    case 'sensitive':
      return RU;
  }
}

function coordinator(actor: Actor, r: Resource): Crud {
  switch (r.type) {
    case 'school':
    case 'audit':
      return NONE;
    case 'user':
    case 'enrollment':
    case 'staff':
    case 'academic_structure':
    case 'teaching_assignment':
    case 'grade':
    case 'attendance':
      return R;
    case 'task_event':
    case 'school_event':
    case 'notice':
      return CRUD;
    case 'observation': {
      const needed = OBSERVATION_COORDINATOR[r.kind];
      return needed === null || actor.coordinatorTypes.has(needed) ? CRU : R;
    }
    case 'self_assessment':
      return actor.coordinatorTypes.has('academica') ? R : NONE;
    case 'message':
      return CR;
    case 'pqrs':
      return RU;
    case 'sensitive':
      return actor.coordinatorTypes.has('orientacion') ? R : NONE;
  }
}

function teacher(actor: Actor, r: Resource): Crud {
  const groups = teacherGroupIds(actor);
  const assignment = (id: number) => actor.assignments.get(id);
  switch (r.type) {
    case 'school':
    case 'audit':
    case 'sensitive':
      return NONE;
    case 'user': // básico: qué campos ve lo decide la ruta
    case 'staff':
    case 'academic_structure':
      return R;
    case 'enrollment':
      return groups.has(r.classGroupId) ? R : NONE;
    case 'teaching_assignment':
      return r.staffId === actor.staffId ? R : NONE;
    case 'task_event':
      return assignment(r.assignmentId) ? CRUD : NONE;
    case 'school_event':
      if (allIn(r.audienceGroupIds, groups)) return CRU;
      return reaches(r.audienceGroupIds, groups) ? R : NONE;
    case 'grade': {
      const a = assignment(r.assignmentId);
      if (!a) return NONE;
      return a.role === 'titular' ? CRU : R; // solo el titular califica
    }
    case 'attendance':
      return groups.has(r.classGroupId) ? CRU : NONE;
    case 'observation':
      return groups.has(r.classGroupId) ? CR : NONE;
    case 'self_assessment':
      return assignment(r.assignmentId) ? CR : NONE;
    case 'message':
      return r.participantUserIds.includes(actor.userId) ? CR : set('create');
    case 'pqrs':
      return r.assignedToUserId === actor.userId ? R : NONE;
    case 'notice':
      if (allIn(r.audienceGroupIds, groups)) return CRUD;
      return reaches(r.audienceGroupIds, groups) ? R : NONE;
  }
}

function student(actor: Actor, r: Resource): Crud {
  const e = actor.enrollment;
  if (!e) return NONE; // sin matrícula activa no ve nada del colegio
  const own = 'studentId' in r && r.studentId === e.studentId;
  const myGroup = new Set([e.classGroupId]);
  switch (r.type) {
    case 'school':
    case 'audit':
      return NONE;
    case 'user': // básico (contactos)
    case 'staff': // nombre y materia
    case 'academic_structure':
      return R;
    case 'enrollment':
    case 'attendance':
    case 'sensitive': // enmascarado: lo hace la ruta
      return own ? R : NONE;
    case 'teaching_assignment':
      return r.classGroupId === e.classGroupId ? R : NONE;
    case 'task_event':
    case 'school_event':
    case 'notice':
      return reaches(r.audienceGroupIds, myGroup) ? R : NONE;
    case 'grade':
      return own && r.published ? R : NONE;
    case 'observation':
      return own ? set('read', 'acknowledge') : NONE;
    case 'self_assessment':
      if (!own) return NONE;
      return r.windowOpen ? CRU : R;
    case 'message':
      return r.participantUserIds.includes(actor.userId) ? CR : set('create');
    case 'pqrs':
      if (r.createdByUserId !== actor.userId) return NONE;
      return CR;
  }
}

/**
 * Corta la petición si no hay permiso. Lo que la persona no puede ver responde
 * 404 (no confirma que existe); si lo ve pero no puede hacer eso, 403.
 */
export function authorize(actor: Actor, action: Action, resource: Resource): void {
  if (can(actor, action, resource)) return;
  if (action !== 'read' && can(actor, 'read', resource)) {
    throw new AppError(403, 'forbidden', 'No tienes permiso para esta acción');
  }
  throw new AppError(404, 'not_found', 'No existe');
}

/** El actor de la petición; 401 si no hay sesión o ya no tiene roles en este colegio. */
export function requireActor(request: { actor: Actor | null; sessionExpired: boolean }): Actor {
  if (request.actor) return request.actor;
  throw request.sessionExpired
    ? new AppError(401, 'session_expired', 'Tu sesión venció; vuelve a entrar')
    : new AppError(401, 'unauthenticated', 'Hay que iniciar sesión');
}
