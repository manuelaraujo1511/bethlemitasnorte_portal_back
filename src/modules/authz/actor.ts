import type { CoordinatorType, Db, Role } from '../../db.js';

export interface ActorAssignment {
  classGroupId: number;
  subjectId: number;
  role: 'titular' | 'reemplazo';
}

/**
 * Quién hace la petición y su alcance en el colegio del host. Se carga una vez
 * por petición con sesión; la política (`can`) decide solo con esto y el recurso.
 */
export interface Actor {
  userId: number;
  /** Colegio del host; null = host de administración (solo platform_admin). */
  schoolId: number | null;
  roles: ReadonlySet<Role>;
  coordinatorTypes: ReadonlySet<CoordinatorType>;
  /** staff_members.id en este colegio, si es personal. */
  staffId: number | null;
  /** Asignaciones vigentes hoy en el año activo, como titular o reemplazo. */
  assignments: ReadonlyMap<number, ActorAssignment>;
  /** Grupos del año activo que dirige. */
  directedGroupIds: ReadonlySet<number>;
  /** Matrícula activa del año activo, si es estudiante. */
  enrollment: { id: number; studentId: number; classGroupId: number } | null;
}

export interface ActorStore {
  /** null si no tiene roles en ese colegio (o, con schoolId null, si no es platform_admin). */
  loadActor(userId: number, schoolId: number | null, today: string): Promise<Actor | null>;
}

/** Fecha local del colegio (YYYY-MM-DD): la vigencia de un reemplazo se cuenta en días del colegio. */
export function localDate(now: Date, timeZone: string): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
}

/** Grupos donde enseña (asignación vigente) o que dirige. */
export function teacherGroupIds(actor: Actor): Set<number> {
  const ids = new Set(actor.directedGroupIds);
  for (const a of actor.assignments.values()) ids.add(a.classGroupId);
  return ids;
}

export function createKyselyActorStore(db: Db): ActorStore {
  return {
    async loadActor(userId, schoolId, today) {
      const roleRows = await db
        .selectFrom('user_roles')
        .select(['role', 'coordinator_type'])
        .where('user_id', '=', userId)
        .where('revoked_at', 'is', null)
        .where((eb) => (schoolId === null ? eb('role', '=', 'platform_admin') : eb('school_id', '=', schoolId)))
        .execute();
      if (roleRows.length === 0) return null;

      const roles = new Set(roleRows.map((r) => r.role));
      const coordinatorTypes = new Set(roleRows.flatMap((r) => (r.coordinator_type ? [r.coordinator_type] : [])));
      const actor: Actor = {
        userId,
        schoolId,
        roles,
        coordinatorTypes,
        staffId: null,
        assignments: new Map(),
        directedGroupIds: new Set(),
        enrollment: null,
      };
      if (schoolId === null) return actor;

      const staff = await db
        .selectFrom('staff_members')
        .select('id')
        .where('school_id', '=', schoolId)
        .where('user_id', '=', userId)
        .where('status', '=', 'active')
        .where('deleted_at', 'is', null)
        .executeTakeFirst();

      if (staff) {
        actor.staffId = staff.id;
        const [assignments, directed] = await Promise.all([
          db
            .selectFrom('teaching_assignments as ta')
            .innerJoin('academic_years as y', 'y.id', 'ta.academic_year_id')
            .select(['ta.id', 'ta.class_group_id', 'ta.subject_id', 'ta.role'])
            .where('ta.school_id', '=', schoolId)
            .where('ta.staff_id', '=', staff.id)
            .where('ta.status', '=', 'active')
            .where('ta.deleted_at', 'is', null)
            .where('y.status', '=', 'active')
            .where((eb) => eb.or([eb('ta.valid_from', 'is', null), eb('ta.valid_from', '<=', today as unknown as Date)]))
            .where((eb) => eb.or([eb('ta.valid_to', 'is', null), eb('ta.valid_to', '>=', today as unknown as Date)]))
            .execute(),
          db
            .selectFrom('class_groups as g')
            .innerJoin('academic_years as y', 'y.id', 'g.academic_year_id')
            .select('g.id')
            .where('g.school_id', '=', schoolId)
            .where('g.director_staff_id', '=', staff.id)
            .where('g.status', '=', 'active')
            .where('g.deleted_at', 'is', null)
            .where('y.status', '=', 'active')
            .execute(),
        ]);
        actor.assignments = new Map(
          assignments.map((a) => [a.id, { classGroupId: a.class_group_id, subjectId: a.subject_id, role: a.role }]),
        );
        actor.directedGroupIds = new Set(directed.map((g) => g.id));
      }

      if (roles.has('student')) {
        const enrollment = await db
          .selectFrom('enrollments as e')
          .innerJoin('students as st', 'st.id', 'e.student_id')
          .innerJoin('academic_years as y', 'y.id', 'e.academic_year_id')
          .select(['e.id', 'e.student_id', 'e.class_group_id'])
          .where('st.school_id', '=', schoolId)
          .where('st.user_id', '=', userId)
          .where('st.status', '=', 'active')
          .where('st.deleted_at', 'is', null)
          .where('e.status', '=', 'active')
          .where('y.status', '=', 'active')
          .executeTakeFirst();
        if (enrollment) {
          actor.enrollment = { id: enrollment.id, studentId: enrollment.student_id, classGroupId: enrollment.class_group_id };
        }
      }
      return actor;
    },
  };
}
