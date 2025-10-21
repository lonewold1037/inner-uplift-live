#!/usr/bin/env bash
set -e

echo "🧠  Starting Inner Uplift Dev Environment..."

# --- Ensure pg_ctl available ---
export PATH="/usr/lib/postgresql/17/bin:$PATH"

# --- Define PostgreSQL dirs and ports ---
export PGDATA="$HOME/.local/share/postgres"
export PGHOST="/tmp/pgsocket"
export PGPORT=5433

# --- Create socket dir ---
mkdir -p "$PGHOST"
chmod 777 "$PGHOST"

# --- Kill any stuck processes first ---
pkill -9 postgres || true
pkill -9 puma || true
pkill -9 vite || true
rm -f "$PGHOST/.s.PGSQL.$PGPORT"* || true

# --- Init DB cluster if missing ---
if [ ! -d "$PGDATA/base" ]; then
  echo "📦 Initializing new PostgreSQL cluster..."
  /usr/lib/postgresql/17/bin/initdb -D "$PGDATA" --auth=trust >/dev/null
fi

# --- Start Postgres ---
echo "🚀  Launching Postgres on port $PGPORT..."
pg_ctl -D "$PGDATA" -l "$HOME/postgres.log" -o "-k $PGHOST -p $PGPORT" start
sleep 2

# --- Create vscode database for default connection ---
createdb -h "$PGHOST" -p "$PGPORT" vscode 2>/dev/null || true

# --- Create role postgres if missing ---
psql -h "$PGHOST" -p "$PGPORT" -d vscode -tAc "SELECT 1 FROM pg_roles WHERE rolname='postgres'" | grep -q 1 \
  || psql -h "$PGHOST" -p "$PGPORT" -d vscode -c "CREATE ROLE postgres SUPERUSER LOGIN PASSWORD 'postgres';"

# --- Create DBs if missing ---
createdb -h "$PGHOST" -p "$PGPORT" -O postgres inner_uplift_v2_development 2>/dev/null || true
createdb -h "$PGHOST" -p "$PGPORT" -O postgres inner_uplift_v2_development_queue 2>/dev/null || true
createdb -h "$PGHOST" -p "$PGPORT" -O postgres inner_uplift_v2_test 2>/dev/null || true
createdb -h "$PGHOST" -p "$PGPORT" -O postgres inner_uplift_v2_test_queue 2>/dev/null || true

# --- Rails setup ---
echo "🧩  Preparing Rails database..."
bin/rails db:prepare

# --- Start Rails + Vite + GoodJob ---
echo "🌈  Running bin/dev (Rails + Vite + GoodJob)..."
exec bin/dev
