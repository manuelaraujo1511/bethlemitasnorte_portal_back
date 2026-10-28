#!/usr/bin/env bash
# Crea una base temporal, aplica migraciones y seeds dos veces (re-ejecucion),
# corre tests/checks.sql y borra la base. No toca ninguna otra base.
#
# Uso:
#   MYSQL_PWD=... db/tests/run.sh                 # cliente mysql local
#   MYSQL="docker exec -i -e MYSQL_PWD camdb mysql -uroot" MYSQL_PWD=... db/tests/run.sh
# Variables: MYSQL (cliente y opciones de conexion, por defecto "mysql -uroot -h127.0.0.1").
# La contrasena va en MYSQL_PWD o en ~/.my.cnf; nunca en este archivo.
set -euo pipefail

DB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MYSQL="${MYSQL:-mysql -uroot -h127.0.0.1}"
DB="campus_test_$(date +%s)_$$"

run() { $MYSQL "$@"; }
cleanup() { run -e "DROP DATABASE IF EXISTS \`$DB\`" || true; }
trap cleanup EXIT

run -e "CREATE DATABASE \`$DB\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci"

files=("$DB_DIR"/migrations/*.sql "$DB_DIR/seed_dev.sql" "$DB_DIR/seed_dev_academic.sql")
for pass in 1 2; do
  for f in "${files[@]}"; do
    run "$DB" < "$f"
  done
  echo "pasada $pass: ${#files[@]} archivos aplicados"
done

run "$DB" -e "SELECT COUNT(*) AS tablas FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'; SELECT COUNT(*) AS vistas FROM information_schema.views WHERE table_schema = DATABASE();"
run "$DB" < "$DB_DIR/tests/checks.sql"
