// Carga del actor contra MySQL con los seeds de desarrollo. Corre solo con
// DB_INTEGRATION=1 (job `db` de CI, o en local con la base de docker-compose).
import { afterAll, describe, expect, it } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { createDb } from '../../src/db.js';
import { createKyselyActorStore } from '../../src/modules/authz/actor.js';

const enabled = process.env.DB_INTEGRATION === '1';

describe.runIf(enabled)('createKyselyActorStore (MySQL + seeds)', () => {
  const db = enabled ? createDb(loadConfig()) : undefined!;
  const store = enabled ? createKyselyActorStore(db) : undefined!;
  afterAll(async () => {
    await db.destroy();
  });

  it('docente titular: sus asignaciones del año activo', async () => {
    // luis.gomez (usuario 2, staff 1): Matemáticas en 3.º B (1) y 3.º A (101).
    const a = await store.loadActor(2, 1, '2026-10-28');
    expect(a?.roles).toEqual(new Set(['teacher']));
    expect(a?.staffId).toBe(1);
    expect([...a!.assignments.keys()].sort((x, y) => x - y)).toEqual([1, 101]);
    expect(a?.assignments.get(1)).toEqual({ classGroupId: 6, subjectId: 1, role: 'titular' });
  });

  it('reemplazo: solo dentro de su vigencia', async () => {
    // elena.vargas (usuario 3, staff 2) reemplaza Inglés de 3.º B (asignación 9) del 14/09 al 09/10.
    const during = await store.loadActor(3, 1, '2026-09-20');
    expect(during?.assignments.get(9)).toEqual({ classGroupId: 6, subjectId: 3, role: 'reemplazo' });
    const after = await store.loadActor(3, 1, '2026-10-28');
    expect(after?.assignments.has(9)).toBe(false);
    // Es directora de 3.º A (seed_dev_school.sql).
    expect(after?.directedGroupIds).toEqual(new Set([5]));
  });

  it('director de grupo', async () => {
    const a = await store.loadActor(6, 1, '2026-10-28');
    expect(a?.directedGroupIds).toEqual(new Set([6]));
  });

  it('estudiante: su matrícula activa', async () => {
    const a = await store.loadActor(15, 1, '2026-10-28');
    expect(a?.roles).toEqual(new Set(['student']));
    expect(a?.enrollment).toEqual({ id: 1, studentId: 1, classGroupId: 6 });
    expect(a?.staffId).toBeNull();
  });

  it('roles acumulados y tipos de coordinación', async () => {
    const a = await store.loadActor(10, 1, '2026-10-28');
    expect(a?.roles).toEqual(new Set(['coordinator', 'school_admin']));
    expect(a?.coordinatorTypes).toEqual(new Set(['academica']));
  });

  it('platform_admin solo en el host de administración', async () => {
    const admin = await store.loadActor(1, null, '2026-10-28');
    expect(admin?.roles).toEqual(new Set(['platform_admin']));
    expect(await store.loadActor(1, 1, '2026-10-28')).toBeNull();
    expect(await store.loadActor(2, null, '2026-10-28')).toBeNull();
  });

  it('sin roles en otro colegio', async () => {
    expect(await store.loadActor(2, 999, '2026-10-28')).toBeNull();
  });
});
