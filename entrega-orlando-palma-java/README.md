# Benchmark API de ordenes: Spring Boot + PostgreSQL

Taller de benchmarking de APIs con Postgres usando JMeter. El analisis completo, con
las tablas de metricas y las capturas, esta en [INFORME.md](INFORME.md).

## Estructura

```
.
├── docker-compose.yml     API + Postgres
├── init.sql               tablas orders y order_items
├── api/                   codigo Spring Boot y Dockerfile multi-stage
├── jmeter/Benchmark.jmx   plan de pruebas
├── scripts/               level.sh, probe.sh, mac.sh, stats_watch.sh,
│                       diag_forwarder.sh, jtl_stats.py, resources.py,
│                       verifica_informe.py
├── evidencias/
│   ├── capturas/          pantallazos por nivel y docker ps
│   ├── resultados/        Summary/Aggregate (csv), metricas (json), resources_report.csv,
│   │                     diagnostico del reenvio, analisis de errores y crudo/
│   ├── busqueda_estres/   barrido para encontrar el punto de estres
│   └── raw/               JTL crudos y muestras de docker stats
├── INFORME.md
└── README.md
```

## Requisitos

- Docker con Compose v2. Las corridas de esta entrega se hicieron en macOS con
  [colima](https://github.com/abiosoft/colima) como runtime.
- JMeter 5.6.3 con Java 8 o superior.
- Python 3 para los scripts de analisis.
- Para reproducir las capturas automaticamente hace falta conceder a la
  aplicacion desde la que se lanzan los scripts los permisos de
  **Grabacion de pantalla** y **Accesibilidad** en Ajustes del Sistema.

Instalacion del entorno en macOS:

```bash
brew install colima docker docker-compose htop
```

```bash
colima start --cpu 4 --memory 4 --disk 40
```

En macOS 13 no hay bottle de `openjdk@21`, asi que `brew install jmeter` intenta
compilar OpenJDK desde fuente y falla si no esta Xcode completo. JMeter 5.6.3 se
instalo descargando el binario oficial de Apache, que funciona con cualquier JDK
reciente:

```bash
curl -fLO https://downloads.apache.org/jmeter/binaries/apache-jmeter-5.6.3.tgz
```

```bash
shasum -a 512 -c apache-jmeter-5.6.3.tgz.sha512 && tar -xzf apache-jmeter-5.6.3.tgz -C ~/tools
```

Maven no hace falta: el JAR se compila dentro de la imagen de build.

El htop de las capturas corre **dentro** de la VM, para que muestre los procesos
reales de los contenedores:

```bash
colima ssh -- sudo apt-get install -y htop
```

## Levantar el servicio

```bash
docker compose up -d --build
```

La API queda en `http://localhost:5002` y Postgres en `localhost:5435`
(usuario y clave `postgres`, base `orders_db`).

## Probar con curl

```bash
curl -s -X POST http://localhost:5002/api/orders \
  -H "Content-Type: application/json" \
  -d '{"customerId":"C123","items":[{"productId":"P1","quantity":2,"price":10.5},{"productId":"P2","quantity":1,"price":5.0}]}'
```

Responde HTTP 201 con `orderId`, `totalAmount` (26.00), `itemsCount` (3) y `processedAt`.

## Abrir el plan en JMeter

```bash
jmeter -t jmeter/Benchmark.jmx -Jusers=50
```

Propiedades configurables con `-J`: `users`, `duration`, `rampup`, `port` y `jtl`.

## Reproducir las corridas

Corrida oficial de un nivel, con GUI y las capturas del enunciado:

```bash
scripts/level.sh 50
```

Sondas headless para buscar el punto de estres:

```bash
scripts/probe.sh 1400 1500 1600
```

Reporte de consumo a partir de las muestras de `docker stats`:

```bash
python3 scripts/resources.py evidencias/raw evidencias/resultados/resources_report.csv
```

Comprobar que las cifras del informe siguen coincidiendo con los CSV:

```bash
python3 scripts/verifica_informe.py
```

Metricas de un JTL concreto:

```bash
python3 scripts/jtl_stats.py evidencias/raw/1120.jtl.gz --json
```

`evidencias/raw` guarda los JTL crudos de cada corrida oficial y los CSV de
`docker stats`. Los JTL van comprimidos con gzip porque en crudo ocupan entre 24
y 38 MB cada uno; `jtl_stats.py` los lee comprimidos o sin comprimir
indistintamente, y las cifras que produce son identicas en ambos casos. Los JTL
de las sondas de la busqueda de estres no se versionan por tamano (son unos
200 MB en total); su resumen completo, con las 14 sondas, esta en
`evidencias/busqueda_estres/busqueda_estres.csv`.

## Limpiar

```bash
docker compose down -v
```
