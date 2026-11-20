#!/usr/bin/env bash
# Corrida oficial de un nivel de carga, con GUI de JMeter y las 5 capturas que
# pide el enunciado (docker stats de API+DB, htop, Summary Report,
# Aggregate Report y JMeter ejecutando), mas una de pantalla completa.
#
# Uso:
#   scripts/level.sh 10
#   scripts/level.sh 100 60 10
#   DURATION=60 RAMPUP=10 scripts/level.sh 1500
#
# Deja en evidencias/:
#   raw/<usuarios>.jtl                   muestras crudas de la corrida
#   raw/<usuarios>_docker_stats.csv      muestreo continuo de docker stats
#   capturas/<usuarios>u_*.png           las capturas del nivel
#   resultados/<usuarios>u_summary.csv   Summary Report calculado del JTL
#   resultados/<usuarios>u_aggregate.csv Aggregate Report calculado del JTL
#   resultados/<usuarios>u_metricas.json metricas resumidas
#
# JMeter se deja ABIERTO al terminar, para la revision.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=mac.sh
source "$ROOT/scripts/mac.sh"

USERS="${1:?uso: $0 <usuarios> [duracion] [rampup]}"
DURATION="${2:-${DURATION:-60}}"
RAMPUP="${3:-${RAMPUP:-10}}"

PORT="${PORT:-5002}"
API_CONTAINER="${API_CONTAINER:-java-api-orders}"
DB_CONTAINER="${DB_CONTAINER:-java-db-orders}"
JMETER="${JMETER:-jmeter}"
SAMPLE_EVERY="${SAMPLE_EVERY:-1}"        # pausa entre lecturas de docker stats
HTOP_CMD="${HTOP_CMD:-colima ssh -- htop}"

# --- posiciones de ventana y coordenadas de clic (calibrables por entorno) ---
read -r SCREEN_W SCREEN_H < <(mac_screen_size)
# Calibrado para una pantalla principal de 1920x1080.
# La y arranca en 25 para no meter la barra de menus dentro de la captura.
STATS_WIN="${STATS_WIN:-0 25 700 290}"           # terminal con docker stats
HTOP_WIN="${HTOP_WIN:-0 325 700 730}"            # terminal con htop
JMETER_WIN="${JMETER_WIN:-710 0 1200 1030}"      # ventana de JMeter
# Desplazamientos respecto al origen REAL de la ventana de JMeter. Las filas del
# arbol miden 20 px: "Spring Boot (5002)" esta en y=113 y, una vez desplegada,
# Summary Report queda en y=193 y Aggregate Report en y=213.
EXPAND_NODE="${EXPAND_NODE:-27 113}"             # triangulo de "Spring Boot (5002)"
SUMMARY_NODE="${SUMMARY_NODE:-130 193}"
AGGREGATE_NODE="${AGGREGATE_NODE:-130 213}"
START_BUTTON="${START_BUTTON:-313 45}"           # triangulo verde de Start

RAWDIR="$ROOT/evidencias/raw"
CAPDIR="$ROOT/evidencias/capturas"
RESDIR="$ROOT/evidencias/resultados"
mkdir -p "$RAWDIR" "$CAPDIR" "$RESDIR"

JTL="$RAWDIR/${USERS}.jtl"
STATS_CSV="$RAWDIR/${USERS}_docker_stats.csv"
JMLOG="$RAWDIR/${USERS}_jmeter.log"

say() { printf '%s\n' "== $* =="; }

# ------------------------------------------------------------- comprobaciones --
for cmd in docker "$JMETER" python3 screencapture osascript; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: falta '$cmd' en el PATH" >&2; exit 1; }
done

if ! docker ps --format '{{.Names}}' | grep -qx "$API_CONTAINER"; then
  echo "error: el contenedor $API_CONTAINER no esta corriendo (docker compose up -d)" >&2
  exit 1
fi

say "comprobando que la API responde en el puerto $PORT"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://localhost:$PORT/api/orders" \
  -H 'Content-Type: application/json' \
  -d '{"customerId":"SMOKE","items":[{"productId":"P1","quantity":1,"price":1.00}]}')"
if [ "$CODE" != "201" ]; then
  echo "error: la API respondio $CODE en vez de 201" >&2
  exit 1
fi
echo "  la API responde 201"

# -------------------------------------------------------------- calentamiento --
# La JVM compila en caliente (JIT): sin este calentamiento la corrida oficial
# mediria sobre todo el arranque del interprete.
if [ "${WARMUP:-1}" = "1" ]; then
  say "calentamiento de la JVM (sonda descartada de 20 s)"
  "$JMETER" -n -t "$ROOT/jmeter/Benchmark.jmx" \
    -Jusers=50 -Jduration=20 -Jrampup=5 "-Jport=$PORT" \
    -Jjtl="$(mktemp -t warmup).jtl" -j "$(mktemp -t warmuplog).log" >/dev/null 2>&1
  echo "  calentamiento terminado"
  sleep 5
fi

# ------------------------------------------------- terminales de monitorizacion --
say "abriendo terminales de docker stats y htop"
mac_close_terminals_matching "docker stats"
mac_close_terminals_matching "htop"

# Cada ventana nueva de Terminal pasa a ser la ventana 1, asi que se coloca
# justo despues de abrirla; si se abrieran las dos seguidas, solo quedaria
# colocada la ultima y la captura de htop fotografiaria el escritorio vacio.
# Se llama a stats_watch.sh en vez de poner el docker stats aqui: su formato
# lleva tabuladores y se pierden al pasar el comando por AppleScript, dejando
# las columnas pegadas unas a otras en la captura.
mac_open_terminal "bash '$ROOT/scripts/stats_watch.sh' $API_CONTAINER $DB_CONTAINER"
sleep 3
# shellcheck disable=SC2086
mac_place_index Terminal 1 $STATS_WIN

mac_open_terminal "$HTOP_CMD"
sleep 3
# shellcheck disable=SC2086
mac_place_index Terminal 1 $HTOP_WIN
mac_activate Terminal

# ------------------------------------------------------ muestreo de docker stats --
say "muestreando docker stats a $STATS_CSV"
echo "ts,name,cpu,mem" > "$STATS_CSV"
(
  while :; do
    TS="$(python3 -c 'import time; print(int(time.time()*1000))')"
    docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}}' \
      "$API_CONTAINER" "$DB_CONTAINER" 2>/dev/null \
      | while IFS= read -r line; do printf '%s,%s\n' "$TS" "$line"; done >> "$STATS_CSV"
    sleep "$SAMPLE_EVERY"
  done
) &
SAMPLER=$!
trap 'kill $SAMPLER 2>/dev/null' EXIT

# ------------------------------------------------------------- JMeter en GUI --
say "abriendo JMeter en GUI con $USERS usuarios, ${DURATION}s, ramp-up ${RAMPUP}s"
rm -f "$JTL"
# Heap acotado a 2 GB: la maquina tiene 8 GB en total y la VM de colima ya
# se lleva 4 GB, asi que un heap mayor dejaria al sistema sin memoria.
export JVM_ARGS="${JVM_ARGS:--Xms512m -Xmx2g}"
"$JMETER" -t "$ROOT/jmeter/Benchmark.jmx" \
  "-Jusers=$USERS" "-Jduration=$DURATION" "-Jrampup=$RAMPUP" \
  "-Jport=$PORT" "-Jjtl=$JTL" -j "$JMLOG" >/dev/null 2>&1 &

if ! mac_wait_window java 90; then
  echo "error: la ventana de JMeter no aparecio" >&2
  exit 1
fi
sleep 6
mac_activate java
# shellcheck disable=SC2086
mac_place java $JMETER_WIN
sleep 2

# Limites reales de la ventana (macOS baja la y por la barra de menus).
WB="$(mac_bounds java)"
# shellcheck disable=SC2086
set -- ${WB:-$JMETER_WIN}
WX="$1"; WY="$2"

# El arbol arranca plegado: hay que desplegar "Spring Boot (5002)" para que
# Summary Report y Aggregate Report queden visibles y clicables al final.
say "desplegando el arbol del plan"
# shellcheck disable=SC2086
set -- $EXPAND_NODE
mac_click $(( WX + $1 )) $(( WY + $2 ))
sleep 2

say "arrancando la prueba (Start)"
mac_activate java
sleep 1
# shellcheck disable=SC2086
set -- $START_BUTTON
mac_click $(( WX + $1 )) $(( WY + $2 )) || mac_key r command
sleep 2

# ------------------------------------------------------ capturas a mitad de carga --
MID=$(( DURATION / 2 ))
say "esperando ${MID}s para capturar a mitad de carga"
sleep "$MID"

say "capturas a mitad de carga"
# Las dos terminales se capturan por region fija, que es donde se colocaron.
# shellcheck disable=SC2086
set -- $STATS_WIN
mac_shot_region "$1" "$2" "$3" "$4" "$CAPDIR/${USERS}u_docker_stats.png"
# shellcheck disable=SC2086
set -- $HTOP_WIN
mac_shot_region "$1" "$2" "$3" "$4" "$CAPDIR/${USERS}u_htop.png"
mac_shot_screen "$CAPDIR/${USERS}u_pantalla_completa.png"
mac_shot_window java "$CAPDIR/${USERS}u_jmeter_ejecutando.png"
echo "  docker_stats, htop, jmeter_ejecutando y pantalla_completa listas"

# ------------------------------------------------------------- fin de la corrida --
REST=$(( DURATION - MID + RAMPUP + 15 ))
say "esperando ${REST}s a que termine la corrida"
sleep "$REST"

# ---------------------------------------------- capturas de Summary y Aggregate --
# Se leen los limites REALES de la ventana: macOS baja la posicion y para
# dejar sitio a la barra de menus, asi que no coinciden con los pedidos.
mac_activate java
sleep 1
WB="$(mac_bounds java)"
if [ -n "$WB" ]; then
  # shellcheck disable=SC2086
  set -- $WB
else
  # shellcheck disable=SC2086
  set -- $JMETER_WIN
fi
WX="$1"; WY="$2"

say "capturando Summary Report"
# shellcheck disable=SC2086
set -- $SUMMARY_NODE
mac_click $(( WX + $1 )) $(( WY + $2 )) && sleep 2
mac_shot_window java "$CAPDIR/${USERS}u_summary_report.png"

say "capturando Aggregate Report"
# shellcheck disable=SC2086
set -- $AGGREGATE_NODE
mac_click $(( WX + $1 )) $(( WY + $2 )) && sleep 2
mac_shot_window java "$CAPDIR/${USERS}u_aggregate_report.png"

# ------------------------------------------------------------------- metricas --
kill $SAMPLER 2>/dev/null
wait $SAMPLER 2>/dev/null
trap - EXIT

if [ ! -s "$JTL" ]; then
  echo "error: no se genero el JTL $JTL" >&2
  exit 1
fi

say "calculando metricas del JTL de esta misma corrida"
python3 "$ROOT/scripts/jtl_stats.py" "$JTL" \
  --summary "$RESDIR/${USERS}u_summary.csv" \
  --aggregate "$RESDIR/${USERS}u_aggregate.csv" \
  --json | tee "$RESDIR/${USERS}u_metricas.json"
echo

say "filas guardadas en la base de datos"
docker exec "$DB_CONTAINER" psql -U postgres -d orders_db -t -A \
  -c 'SELECT count(*) FROM orders;' 2>/dev/null | tr -d '[:space:]' | sed 's/^/  orders: /'
echo
docker exec "$DB_CONTAINER" psql -U postgres -d orders_db -t -A \
  -c 'SELECT count(*) FROM order_items;' 2>/dev/null | tr -d '[:space:]' | sed 's/^/  order_items: /'
echo

say "nivel de $USERS usuarios terminado (JMeter queda abierto)"
