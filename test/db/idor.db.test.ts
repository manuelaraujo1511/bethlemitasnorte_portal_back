// S1.2: IDOR con actores cargados de MySQL (seeds de desarrollo, datos sintéticos).
// Corre solo con DB_INTEGRATION=1, igual que actor.db.test.ts.
import { afterAll, describe, expect, it } from 'vitest';
import { loadConfig } from '../../src/config.js';
import { createDb } from '../../src/db.js';
import { createKyselyActorStore } from '../../src/modules/authz/actor.js';
import { crossSchoolResources, expectHidden, oneOfEachType, peerResources, peersOf } from '../support/idor.js';

const enabled = process.env.DB_INTEGRATION === '1';
const TODAY = '2026-10-28';

// Universo del seed: 10 grupos, 8 docentes (staff 1-8), asignaciones 1-8 (3.º B) y 101-104 (3.º A),
// estudiantes 1 (Ana, 3.º B), 101 (3.º B) y 130 (3.º A).
const universe = {
  schoolId: 1,
  studentIds: [1, 101, 130],
  groupIds: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  assignmentIds: [1, 2, 3, 4, 5, 6, 7, 8, 101, 102, 103, 104],
  staffIds: [1, 2, 3, 4, 5, 6, 7, 8],
  userIds: [2, 3, 4, 5, 6, 7, 8, 9, 15, 101, 130],
};
const students = [15, 101, 130];
const teachers = [2, 3, 4, 5, 6, 7, 8, 9];
const staffOfCoordination = [10, 11, 12, 13, 14];

describe.runIf(enabled)('IDOR con actores del seed (MySQL)', () => {
  const db = enabled ? createDb(loadConfig()) : undefined!;
  const store = enabled ? createKyselyActorStore(db) : undefined!;
  afterAll(async () => {
    await db.destroy();
  });

  async function load(userId: number, schoolId: number | null = 1) {
    const actor = await store.loadActor(userId, schoolId, TODAY);
    expect(actor, `usuario ${userId} debe tener roles en el colegio ${schoolId}`).not.toBeNull();
    return actor!;
  }

  it.each([...students, ...teachers])('usuario %i: nada de lo ajeno dentro del colegio', async (userId) => {
    const actor = await load(userId);
    const resources = peerResources(peersOf(actor, universe));
    expect(resources.length).toBeGreaterThan(20);
    expectHidden(`usuario ${userId}`, actor, resources);
  });

  it.each([...students, ...teachers, ...staffOfCoordination])('usuario %i: nada de otro colegio', async (userId) => {
    const actor = await load(userId);
    expectHidden(`usuario ${userId}`, actor, crossSchoolResources(2, userId));
  });

  it('platform_admin del seed: sin datos de menores', async () => {
    const admin = await load(1, null);
    const minors = oneOfEachType(1, { studentId: 1, groupId: 6, assignmentId: 1, staffId: 1, userId: 1 }).filter(
      (r) => !['school', 'audit'].includes(r.type) && !(r.type === 'user' && r.role === 'school_admin'),
    );
    expectHidden('platform_admin', admin, minors);
  });

  it('un usuario de un colegio no tiene actor en otro: 0 roles, no hay nada que autorizar', async () => {
    for (const userId of [...students, ...teachers, ...staffOfCoordination]) {
      expect(await store.loadActor(userId, 2, TODAY), `usuario ${userId} en colegio 2`).toBeNull();
    }
  });

  it('un estudiante no se carga como actor del host de administración', async () => {
    expect(await store.loadActor(15, null, TODAY)).toBeNull();
  });
});
