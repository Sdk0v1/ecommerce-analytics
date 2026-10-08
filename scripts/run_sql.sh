#!/usr/bin/env bash
# Запускає всі SQL-файли в правильному порядку на базі даних, заданій у
# стандартних змінних середовища PG* (PGHOST, PGUSER, PGPASSWORD, PGDATABASE).
# Запускати потрібно з кореня репозиторію (шляхи в \copy відносні до нього).
set -euo pipefail

SQL_FILES=(
  00_create_tables
  01_analytics_views
  monthly_kpis
  revenue_analysis
  customer_retention
  cohort_analysis
  delivery_analysis
  99_export_tables
)

mkdir -p reports/tables
for f in "${SQL_FILES[@]}"; do
  echo "::group::SQL/$f.sql"
  psql -v ON_ERROR_STOP=1 -q -f "SQL/$f.sql" > /dev/null
  echo "ok SQL/$f.sql"
  echo "::endgroup::"
done
