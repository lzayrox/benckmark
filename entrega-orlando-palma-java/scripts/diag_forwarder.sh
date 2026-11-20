#!/usr/bin/env bash
# Comprueba si el "Connection refused" que aparece bajo carga lo provoca la API
# o el reenvio de puertos que colima mantiene entre macOS y la VM.
#
# Lanza ab contra la IP del contenedor DESDE DENTRO de la VM, es decir sin pasar
# por el reenvio. Si a la misma concurrencia que falla desde macOS aqui no hay
# ni un fallo de conexion, el limite es del reenvio y no de la API.
#
# El ab que trae macOS (2.3 r1901567) aborta con "apr_socket_connect(): Invalid
# argument (22)" incluso con concurrencia 100, asi que el camino de macOS no se
# puede medir con esta herramienta; para ese lado valen las cifras de JMeter.
#
# Uso: scripts/diag_forwarder.sh [peticiones] [concurrencia...]

set -uo pipefail
N="${1:-60000}"
shift || true
LEVELS=("${@:-1500}")
BODY='{"customerId":"C123","items":[{"productId":"P1","quantity":2,"price":10.5},{"productId":"P2","quantity":1,"price":5.0}]}'

command -v colima >/dev/null || { echo "falta colima" >&2; exit 1; }
command -v docker >/dev/null || { echo "falta docker" >&2; exit 1; }

IP="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' java-api-orders 2>/dev/null)"
[ -n "$IP" ] || { echo "no se encontro el contenedor java-api-orders" >&2; exit 1; }

echo "== preparando ab dentro de la VM =="
colima ssh -- sh -c 'command -v ab >/dev/null || (sudo apt-get update -qq && sudo apt-get install -y -qq apache2-utils)' >/dev/null 2>&1
colima ssh -- ab -V 2>&1 | head -1
printf '%s' "$BODY" | colima ssh -- sh -c 'cat > /tmp/abbody.json'
echo "IP del contenedor dentro de la VM: $IP"
echo

for C in "${LEVELS[@]}"; do
  echo "== dentro de la VM -> $IP:5002, $N peticiones, concurrencia $C =="
  colima ssh -- sh -c "ulimit -n 65535; ab -n $N -c $C -p /tmp/abbody.json -T application/json -k http://$IP:5002/api/orders" 2>&1 \
    | grep -E "Complete requests|Failed requests|^ +\(Connect|Requests per second|Time per request" \
    | sed 's/^/   /'
  echo
done

echo "Nota: los 'Failed requests' de tipo Length no son errores, solo reflejan"
echo "que el cuerpo de la respuesta varia unos bytes porque el orderId es un UUID."
echo "Lo que importa es el contador Connect, que debe estar en 0."
