#!/usr/bin/env bash
# Runs every SQL file in the correct order against the database set in the
# standard PG* environment variables (PGHOST, PGUSER, PGPASSWORD, PGDATABASE).
# Must be run from the repository root (the \copy paths are relative to it).
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
