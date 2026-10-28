import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import type { Connection } from 'mysql2/promise';

const MIGRATION_FILE = /^(\d{4}_[a-z0-9_]+)\.sql$/;

export interface Migration {
  version: string;
  file: string;
}

/** Migraciones del directorio, en orden numérico. */
export async function listMigrations(dir: string): Promise<Migration[]> {
  const entries = await readdir(dir).catch((err: NodeJS.ErrnoException) => {
    if (err.code === 'ENOENT') return [];
    throw err;
  });
  return entries
    .map((name) => MIGRATION_FILE.exec(name))
    .filter((m): m is RegExpExecArray => m !== null)
    .map((m) => ({ version: m[1]!, file: path.join(dir, m[0]) }))
    .sort((a, b) => a.version.localeCompare(b.version));
}

/**
 * Parte un script en lotes que el servidor entiende. `DELIMITER` es una
 * directiva del cliente `mysql`, no SQL: mientras el delimitador es `;` el
 * bloque va entero (multipleStatements); con otro delimitador, cada sentencia
 * va sola (p. ej. un CREATE PROCEDURE con `;` internos).
 */
export function splitSqlScript(script: string): string[] {
  const batches: string[] = [];
  let delimiter = ';';
  let buffer: string[] = [];

  const flush = () => {
    const text = buffer.join('\n');
    buffer = [];
    if (delimiter === ';') {
      if (hasSql(text)) batches.push(text);
      return;
    }
    for (const part of text.split(delimiter)) {
      if (hasSql(part)) batches.push(part);
    }
  };

  for (const line of script.split(/\r?\n/)) {
    const directive = /^\s*DELIMITER\s+(\S+)\s*$/i.exec(line);
    if (directive) {
      flush();
      delimiter = directive[1]!;
      continue;
    }
    buffer.push(line);
  }
  flush();
  return batches;
}

function hasSql(text: string): boolean {
  const withoutComments = text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*--.*$/gm, '');
  return withoutComments.replace(/;/g, '').trim().length > 0;
}

export async function runSqlFile(conn: Connection, file: string): Promise<void> {
  const script = await readFile(file, 'utf8');
  for (const batch of splitSqlScript(script)) {
    await conn.query(batch);
  }
}

export async function appliedVersions(conn: Connection): Promise<Set<string>> {
  const [tables] = await conn.query(
    "SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = 'schema_migrations'",
  );
  if ((tables as unknown[]).length === 0) return new Set();
  const [rows] = await conn.query('SELECT version FROM schema_migrations');
  return new Set((rows as { version: string }[]).map((r) => r.version));
}
