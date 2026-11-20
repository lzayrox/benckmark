#!/usr/bin/env bash
# Sondas headless para buscar el punto de estres sin tener que hacer una corrida
# completa con GUI por cada nivel.
#
# Uso:
#   scripts/probe.sh 500 1500 3000
#   DURATION=30 RAMPUP=10 scripts/probe.sh 1400 1420 1440
#
# Cada sonda ejecuta JMeter en modo -n (sin GUI), guarda su JTL y su log en
# evidencias/busqueda_estres/raw/ y agrega una linea al CSV acumulado
# evidencias/busqueda_estres/busqueda_estres.csv.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DURATION="${DURATION:-30}"
RAMPUP="${RAMPUP:-10}"
PORT="${PORT:-5002}"
PAUSE="${PAUSE:-10}"          # segundos de reposo entre sondas
JMETER="${JMETER:-jmeter}"

DIR="$ROOT/evidencias/busqueda_estres"
RAW="$DIR/raw"
LOG="$DIR/busqueda_estres.csv"
mkdir -p "$RAW"

if [ "$#" -eq 0 ]; then
  echo "uso: $0 <usuarios> [usuarios...]" >&2
  exit 1
fi

if ! command -v "$JMETER" >/dev/null 2>&1; then
  echo "error: no se encontro '$JMETER' en el PATH" >&2
  exit 1
fi

if [ ! -f "$LOG" ]; then
  echo 'users,duration_s,samples,avg_ms,p90_ms,p95_ms,throughput,error_pct,errors_5xx,errors_socket,errors_other,top_error' > "$LOG"
fi

# Heap acotado a 2 GB: la maquina tiene 8 GB en total y la VM de colima ya
# se lleva 4 GB, asi que un heap mayor dejaria al sistema sin memoria.
export JVM_ARGS="${JVM_ARGS:--Xms512m -Xmx2g}"

for USERS in "$@"; do
  # Si un nivel se repite (para ver la varianza entre corridas), la segunda
  # sonda NO debe pisar el JTL de la primera: se le anade un sufijo.
  JTL="$RAW/probe_${USERS}.jtl"
  LOGF="$RAW/probe_${USERS}.log"
  N=2
  while [ -e "$JTL" ]; do
    JTL="$RAW/probe_${USERS}_${N}.jtl"
    LOGF="$RAW/probe_${USERS}_${N}.log"
    N=$((N + 1))
  done
  echo "== sonda de $USERS usuarios (${DURATION}s, ramp-up ${RAMPUP}s) -> $(basename "$JTL") =="

  "$JMETER" -n -t "$ROOT/jmeter/Benchmark.jmx" \
    "-Jusers=$USERS" "-Jduration=$DURATION" "-Jrampup=$RAMPUP" \
    "-Jport=$PORT" "-Jjtl=$JTL" \
    -j "$LOGF" >/dev/null 2>&1

  if [ ! -s "$JTL" ]; then
    echo "  error: la sonda no genero muestras (ver $LOGF)" >&2
    continue
  fi

  METRICS="$(python3 "$ROOT/scripts/jtl_stats.py" "$JTL" --json)" || continue

  python3 - "$USERS" "$DURATION" "$LOG" "$METRICS" <<'PY'
import json, sys
users, duration, log, metrics = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
m = json.loads(metrics)
top = str(m["top_error"]).replace(",", ";")
row = [users, duration, m["samples"], m["avg"], m["p90"], m["p95"],
       m["throughput"], m["error_pct"], m["errors_5xx"], m["errors_socket"],
       m["errors_other"], top]
with open(log, "a", encoding="utf-8") as fh:
    fh.write(",".join(map(str, row)) + "\n")
print(f"  avg={m['avg']}ms p90={m['p90']}ms p95={m['p95']}ms "
      f"tp={m['throughput']}req/s err={m['error_pct']}% "
      f"5xx={m['errors_5xx']} socket={m['errors_socket']} otros={m['errors_other']} [{top}]")
PY

  sleep "$PAUSE"
done

echo
echo "resumen acumulado en $LOG"
