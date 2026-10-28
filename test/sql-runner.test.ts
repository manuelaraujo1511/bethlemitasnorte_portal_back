import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { listMigrations, splitSqlScript } from '../scripts/sql-runner.js';

describe('splitSqlScript', () => {
  it('deja junto un script sin DELIMITER', () => {
    const script = 'CREATE TABLE a (id INT);\nINSERT INTO a VALUES (1);';
    expect(splitSqlScript(script)).toEqual([script]);
  });

  it('separa un procedimiento escrito con DELIMITER', () => {
    const script = [
      'DROP PROCEDURE IF EXISTS p;',
      'DELIMITER $$',
      'CREATE PROCEDURE p()',
      'BEGIN',
      '  SELECT 1;',
      '  SELECT 2;',
      'END$$',
      'DELIMITER ;',
      'CALL p();',
      'DROP PROCEDURE p;',
    ].join('\n');
    const batches = splitSqlScript(script).map((b) => b.trim());
    expect(batches).toEqual([
      'DROP PROCEDURE IF EXISTS p;',
      'CREATE PROCEDURE p()\nBEGIN\n  SELECT 1;\n  SELECT 2;\nEND',
      'CALL p();\nDROP PROCEDURE p;',
    ]);
  });

  it('descarta lotes con solo comentarios', () => {
    expect(splitSqlScript('-- nada\n/* tampoco */\n')).toEqual([]);
  });
});

describe('listMigrations', () => {
  it('ordena por número e ignora otros archivos', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'mig-'));
    for (const f of ['0002_b.sql', '0001_a.sql', 'README.md', 'seed_dev.sql']) {
      await writeFile(path.join(dir, f), '');
    }
    const versions = (await listMigrations(dir)).map((m) => m.version);
    expect(versions).toEqual(['0001_a', '0002_b']);
  });

  it('devuelve vacío si el directorio no existe', async () => {
    expect(await listMigrations('/no/existe')).toEqual([]);
  });
});
