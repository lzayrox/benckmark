# Informe de benchmarking: API de órdenes con Spring Boot + PostgreSQL

**Autor:** Orlando Palma
**Stack:** Java 21 + Spring Boot 3.4.0 + PostgreSQL 16 (Docker)
**Fecha:** 20 de noviembre de 2026

## 1. Descripción del microservicio

El servicio expone `POST /api/orders` (puerto 5002). Recibe un `customerId` y una lista de `items` (`productId`, `quantity`, `price`) y hace lo siguiente:

- Calcula `totalAmount` = Σ(`quantity` × `price`), redondeado a 2 decimales con `HALF_UP`, e `itemsCount` = Σ(`quantity`).
- Genera un `orderId` con formato `ORD-<uuid>`.
- Abre una transacción con `@Transactional`: toma una conexión del pool de HikariCP, inserta la fila en `orders` (devolviendo `created_at` con `RETURNING`) y luego **todos** los ítems en `order_items` con un único `batchUpdate`. Si algo falla, Spring hace `ROLLBACK`.
- Responde HTTP 201 con el resumen. Si falta `customerId` o `items`, o si algún ítem trae `quantity` ≤ 0 o `price` negativo, responde 400.

Los precios se manejan como `BigDecimal` en toda la cadena, no como `double`, para no perder precisión al acumular el total.

Prueba manual con el cuerpo exacto del enunciado (`C123`, `P1` 2 × 10.5, `P2` 1 × 5.0). Respuesta (HTTP 201):

```json
{"orderId":"ORD-f9009646-579e-4e88-a279-023bb59da41d","customerId":"C123","totalAmount":26.00,"itemsCount":3,"processedAt":"2026-11-20T19:57:14.074532Z"}
```

Verificación en Postgres de esa orden: 1 fila en `orders` (`total_amount = 26.00`, `items_count = 3`) y 2 filas en `order_items`. La salida completa de la petición y de los `SELECT` está en [`evidencias/resultados/verificacion_endpoint.txt`](evidencias/resultados/verificacion_endpoint.txt).

El cuerpo que usa JMeter (2 × 15.50 + 1 × 25.00) da `totalAmount` 56.00 e `itemsCount` 3.

Archivos principales: `api/src/main/java/com/benchmark/orders/OrderController.java` (validación), `OrderService.java` (cálculo de totales) y `OrderRepository.java` (transacción y `batchUpdate`).

## 2. Base de datos y docker-compose

- `init.sql` crea las tablas `orders` (`id`, `order_id` único, `customer_id`, `total_amount NUMERIC(10,2)`, `items_count`, `created_at`) y `order_items` (`id`, `order_id`, `product_id`, `quantity`, `price`). Se ejecuta automáticamente al crear el volumen.
- `docker-compose.yml` levanta dos servicios:

| Servicio | Contenedor | Imagen | Puerto host |
|---|---|---|---|
| api | `java-api-orders` | build de `./api` (multi-stage: Maven JDK 21 → `eclipse-temurin:21-jre`) | 5002 |
| db | `java-db-orders` | `postgres:16` | 5435 (→ 5432) |

La API espera a que Postgres pase el healthcheck (`pg_isready`) antes de arrancar. Los datos viven en el volumen `dbdata`. Los puertos 5002 y 5435 y los nombres de contenedor evitan choques con las demás entregas del taller.

## 3. Entorno de pruebas

| Componente | Detalle |
|---|---|
| SO | macOS 13.0.1 (Ventura) |
| CPU / RAM | Apple M1 (8 núcleos), 8 GB |
| Docker | Docker 29.5.2 sobre colima 0.10.3 (Virtualization.Framework, aarch64), VM con **4 CPUs y 3.81 GiB** |
| JMeter | 5.6.3 sobre Java 20.0.2, heap `-Xms512m -Xmx2g`, modo GUI para las corridas oficiales |
| API | Spring Boot 3.4.0 sobre Temurin 21.0.13 (dentro del contenedor), HikariCP con 30 conexiones, Tomcat con 200 hilos y `accept-count` 100 |
| Base de datos | PostgreSQL 16.16 |

Tres limitaciones del entorno que condicionan todas las cifras, y conviene tener presentes antes de comparar con los demás stacks del grupo:

1. **Todo corre en la misma máquina de 8 GB.** La VM de colima se lleva 4 GB (API + Postgres) y en los otros 4 GB viven macOS y JMeter. El cliente **compite por CPU** con lo que está midiendo.
2. **Docker no corre nativo, sino dentro de una VM de Linux.** En macOS los puertos publicados de los contenedores llegan al host a través de un reenvío de puertos de colima. La sección 6 demuestra que ese reenvío, y no la API, es lo que marca el techo de las mediciones.
3. **El heap de JMeter está limitado a 2 GB** por la memoria disponible, cuando lo habitual en estas pruebas es darle bastante más.

`htop` se ejecutó **dentro de la VM** (`colima ssh -- htop`), así que las capturas muestran los procesos reales de los contenedores (`java -XX:MaxRAMPercentage=75` y `postgres: orders_db`) y los 4 núcleos de la VM. Solo hubo un API levantado durante las pruebas.

En las capturas de `htop` conviene mirar las barras de los 4 núcleos, no el `CPU%` de cada fila: htop está en modo hilos (se ve en el contador `Tasks: N, M thr`), así que lo que lista son los hilos de la JVM por separado, cada uno con su porcentaje pequeño. La suma de todos ellos es la que corresponde al 116-123 % que marca `docker stats` para el proceso entero.

## 4. Test Plan de JMeter (`jmeter/Benchmark.jmx`)

```
Benchmark Spring Boot (Test Plan)
├── setUp Thread Group
│   └── Limpiar tablas (TRUNCATE)   -> docker exec java-db-orders psql ... TRUNCATE TABLE order_items, orders RESTART IDENTITY;
├── Thread Group "Spring Boot (5002)"
│   ├── HTTP Request Defaults       (localhost, puerto ${__P(port,5002)}, /api/orders)
│   ├── HTTP Header Manager         (Content-Type: application/json)
│   └── HTTP Request "POST /api/orders"
├── Summary Report
├── Aggregate Report
└── Simple Data Writer              (archivo ${__P(jtl,)})
```

Parámetros del Thread Group, configurables con `-J`:

| Propiedad | Uso | Valor por defecto |
|---|---|---|
| `users` | hilos (usuarios) | 10 |
| `rampup` | ramp-up en segundos | 5 |
| `duration` | duración del scheduler en segundos | 30 |
| `port` | puerto de la API | 5002 |
| `jtl` | archivo de salida del Simple Data Writer | vacío |

En las corridas oficiales se usó duración de **60 s** y ramp-up de **10 s**. El sampler tiene timeout de conexión de 5 s, timeout de respuesta de 10 s y keep-alive activo. El `setUp Thread Group` hace `TRUNCATE ... RESTART IDENTITY` antes de cada corrida, así todas empiezan con tablas vacías. Se comprobó que funciona insertando una fila a mano antes de una corrida y verificando que desaparecía.

Como la JVM compila en caliente (JIT), antes de cada corrida oficial se ejecuta una sonda de calentamiento de 20 s que se descarta. Sin ella, la medición estaría dominada por el arranque del intérprete.

Cuerpo del POST:

```json
{
  "customerId": "CUST-${__Random(1,1000)}",
  "items": [
    { "productId": "PROD-${__Random(1,50)}", "quantity": 2, "price": 15.50 },
    { "productId": "PROD-${__Random(51,100)}", "quantity": 1, "price": 25.00 }
  ]
}
```

## 5. Resultados por escenario

Los escenarios son 10 / 50 / 100 usuarios, como pide la sección de entregables del enunciado. El punto 5 del enunciado menciona 20/70/150, pero se siguió la sección de entregables, que es la que define lo que hay que entregar; se deja constancia de la diferencia aquí. El cuarto escenario es el nivel de estrés encontrado (sección 6).

Las cifras salen del JTL de la misma corrida (procesado con `scripts/jtl_stats.py`) y coinciden con el Aggregate Report de las capturas. Cada corrida duró 60 s con ramp-up de 10 s.

| Escenario | Usuarios | Muestras | Average (ms) | P90 (ms) | P95 (ms) | P99 (ms) | Min (ms) | Max (ms) | Throughput (req/s) | % Error | Observaciones personales |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Baja | 10 | 269 290 | 2 | 3 | 3 | 6 | 0 | 94 | 4491.69 | 0.00 | Latencia casi plana (desv. est. 1.64 ms). Con 10 usuarios la API ya pide ~95 % de un núcleo y la base de datos otro tanto: las dos arrancan parejas desde el principio. |
| Media | 50 | 313 480 | 8 | 14 | 16 | 24 | 1 | 261 | 5226.93 | 0.00 | El mejor throughput de las cuatro corridas. Multiplicar por 5 los usuarios solo multiplicó por 4 la latencia y además subió el rendimiento un 16 %: a 10 usuarios el sistema estaba desaprovechado. |
| Alta | 100 | 281 175 | 19 | 39 | 48 | 77 | 1 | 200 | 4683.21 | 0.00 | Aquí aparece la meseta: el throughput baja un 10 % respecto a 50 usuarios y la latencia se duplica. Las peticiones de más empiezan a hacer cola. Cero errores. |
| Estrés | 1120 | 184 477 | 337 | 473 | 563 | 1077 | 0 | 12 835 | 2956.36 | 0.19 | Latencia media de 337 ms y cola larga (máximo de 12.8 s). Aparecen los primeros errores en cantidad no anecdótica y el throughput cae a su mínimo. Cero errores 5xx. |

Nota sobre el P99: `jtl_stats.py` usa el método del rango más cercano y JMeter interpola, así que el P99 puede diferir en unos pocos milisegundos respecto a la captura (1077 frente a 1074 en el nivel de estrés). El resto de las cifras coincide exactamente.

## 6. Búsqueda del punto de estrés

**Método.** El enunciado sugiere subir de 20 en 20 hasta notar estrés. Partiendo de 100 eso habría tomado decenas de corridas, así que se hizo en tres pasos con sondas headless de 30 s (ramp-up 10 s, `scripts/probe.sh`):

1. **Exploración gruesa** con 500, 1500 y 3000 usuarios, para acotar el orden de magnitud.
2. **Bisección** con 700, 900, 1100 y 1300 para cerrar la zona donde aparecen los primeros errores.
3. **Refinamiento en múltiplos de 20** (920, 960, 1000, 1040, 1080, 1100 repetida y 1120).

Resultados completos (`evidencias/busqueda_estres/busqueda_estres.csv`), en el orden ejecutado. Todas las sondas duraron 30 s:

| # | Usuarios | Muestras | Average (ms) | P90 (ms) | P95 (ms) | Throughput (req/s) | % Error | Errores 5xx | Errores de socket |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 500 | 117 865 | 106 | 212 | 267 | 3910.45 | 0.00 | 0 | 0 |
| 2 | 1500 | 96 563 | 391 | 472 | 614 | 3018.82 | 1.75 | 0 | 1689 |
| 3 | 3000 | 111 976 | 503 | 481 | 1921 | 3414.11 | 4.40 | 0 | 4927 |
| 4 | 700 | 121 850 | 144 | 257 | 307 | 4036.37 | 0.00 | 0 | 0 |
| 5 | 900 | 110 173 | 206 | 337 | 399 | 3634.03 | 0.00 | 0 | 0 |
| 6 | 1100 (1.ª) | 110 338 | 252 | 374 | 446 | 3595.95 | 0.02 | 0 | 24 |
| 7 | 1300 | 113 114 | 289 | 373 | 442 | 3544.78 | 0.69 | 0 | 784 |
| 8 | 920 | 101 307 | 229 | 379 | 465 | 3328.74 | 0.00 | 0 | 0 |
| 9 | 960 | 125 296 | 194 | 314 | 360 | 4133.27 | 0.00 | 0 | 0 |
| 10 | 1000 | 113 991 | 221 | 354 | 408 | 3756.62 | 0.02 | 0 | 21 |
| 11 | 1040 | 118 615 | 219 | 343 | 402 | 3853.14 | 0.02 | 0 | 21 |
| 12 | 1080 | 113 863 | 241 | 370 | 435 | 3676.32 | 0.02 | 0 | 23 |
| 13 | 1100 (2.ª) | 112 627 | 247 | 361 | 420 | 3653.87 | 0.02 | 0 | 23 |
| 14 | 1120 | 92 937 | 305 | 434 | 527 | 2909.01 | 0.20 | 0 | 183 |

Aviso sobre la sonda 6: la versión de `scripts/probe.sh` con la que se ejecutó el barrido nombraba el JTL solo por el número de usuarios, así que la segunda sonda de 1100 (fila 13) sobrescribió el JTL de la primera (fila 6). La fila 6 de la tabla procede del CSV que el script escribió en su momento, pero es la única de las catorce cuyo JTL crudo no se conserva y, por tanto, la única que no se puede recalcular. El script ya está corregido para que un nivel repetido no pise el JTL del anterior.

**Conclusión.** Hasta 960 usuarios no hay un solo error. Entre 1000 y 1100 aparece un goteo que se mantiene plano en 0.02 % a lo largo de cuatro niveles distintos (21, 21, 23 y 24 errores sobre unas 113 000 peticiones), y la sonda de 1100 repetida dio prácticamente lo mismo las dos veces (24 y 23), así que no es ruido de una corrida suelta. En **1120** los errores se multiplican por ocho de golpe (183 frente a 23) y el throughput cae a 2909 req/s, el más bajo de todo el barrido. Ese salto es el codo de la curva, y por eso se eligió **1120 usuarios** como nivel de estrés oficial. De ahí para arriba el deterioro es continuo: 0.69 % a 1300, 1.75 % a 1500 y 4.40 % a 3000.

### 6.1. El límite medido no es el de la API

Los errores no son los que cabría esperar de un servidor saturado. **No hubo ni un solo 5xx en ninguna prueba**, y en el nivel de estrés el error dominante es `HttpHostConnectException: Connection refused`: la conexión ni siquiera llega a establecerse. Además la latencia media a 3000 usuarios es de medio segundo, lejísimos del timeout de respuesta de 10 s. Dos indicios más apuntaban en la misma dirección:

- El log de la API tiene **25 líneas en total**, todas del arranque: ni un error ni un rechazo, pese a las 4927 conexiones fallidas de la sonda de 3000 usuarios.
- El `somaxconn` dentro del contenedor es 4096, muy por encima de los 200 hilos de Tomcat más los 100 de `accept-count`.

Para comprobarlo se lanzó la misma concurrencia por dos caminos distintos (`scripts/diag_forwarder.sh`), uno pasando por el reenvío de puertos de colima y otro atacando la IP del contenedor desde dentro de la VM:

| Camino | Concurrencia | Keep-alive | Throughput | Fallos de conexión |
|---|---|---|---|---|
| macOS → `localhost:5002`, con reenvío (JMeter) | 1500 | sí | 3018.82 req/s | 1689 |
| Dentro de la VM → IP del contenedor, sin reenvío (ab) | 1500 | sí | 7698.22 req/s | **0** |
| Dentro de la VM, sin reenvío (ab) | 200 | sí | 8038.18 req/s | **0** |
| Dentro de la VM, sin reenvío (ab) | 100 | sí | 8007.03 req/s | **0** |
| Dentro de la VM, sin reenvío (ab) | 1500 | **no** | 6631.48 req/s | **0** |

La última fila responde a la objeción más seria que se le puede hacer a esta comparación: con keep-alive, `ab` abre solo tantas conexiones como concurrencia y luego las reutiliza, mientras que los fallos de JMeter se producen justo **al establecer** la conexión. Por eso se repitió la prueba **sin** keep-alive, donde cada una de las 60 000 peticiones abre su propia conexión, que es el escenario en el que un rechazo tendría que aparecer. Siguió dando **cero fallos de conexión**.

Con la **misma** concurrencia de 1500, la API atiende 60 000 peticiones sin un solo fallo de conexión cuando se la ataca desde dentro de la VM, y acumula 1689 rechazos cuando se la ataca desde macOS a través del reenvío. Y sostiene entre 7200 y 8800 req/s por dentro, frente a los 2900–5200 que se miden por fuera.

Es decir: **el techo de throughput y los rechazos de conexión son del camino macOS → VM, no de Spring Boot. La API no llegó a saturarse en ninguna de las pruebas.** El detalle está en [`evidencias/resultados/diagnostico_reenvio.txt`](evidencias/resultados/diagnostico_reenvio.txt).

Una salvedad honesta: las cifras de `ab` y las de JMeter no son directamente comparables en valor absoluto, porque son clientes distintos con overhead distinto. Y el camino de macOS no se pudo medir con `ab` porque la versión que trae macOS (2.3 r1901567) aborta con `apr_socket_connect(): Invalid argument (22)` incluso con concurrencia 100, un defecto conocido de esa versión que no tiene relación con el reenvío. Lo que sí es robusto, y no depende de la herramienta ni del uso de keep-alive, es la diferencia cualitativa: **cero fallos de conexión frente a miles, con la misma concurrencia.**

Las salidas crudas de todas estas comprobaciones están en [`evidencias/resultados/crudo/`](evidencias/resultados/crudo/): [`docker_logs_api.txt`](evidencias/resultados/crudo/docker_logs_api.txt) (el log completo de la API, 25 líneas, cero ERROR/WARN/Exception), [`somaxconn.txt`](evidencias/resultados/crudo/somaxconn.txt), [`ab_con_keepalive.txt`](evidencias/resultados/crudo/ab_con_keepalive.txt) y [`ab_sin_keepalive_c1500.txt`](evidencias/resultados/crudo/ab_sin_keepalive_c1500.txt).

### 6.2. Qué pasó con los datos en el nivel de estrés

Desglose de los 354 errores de la corrida oficial de 1120 usuarios:

| Errores | Mensaje | ¿Llegó a la API? |
|---|---|---|
| 182 | `Connection refused` | No |
| 108 | `Read timed out` | Sí |
| 61 | `Connection reset` | Ambiguo |
| 3 | `Broken pipe` | Ambiguo |

Al terminar, `orders` tenía **184 228 filas** frente a **184 123 peticiones exitosas** según JMeter. Hay **105 filas de más**, no de menos: son pedidos que la API recibió, procesó y guardó, pero cuya respuesta el cliente dio por perdida. No se perdió ni un solo pedido de los que llegaron; lo que hubo fueron respuestas tardías.

Y la transacción cumplió: de los 184 228 pedidos, **ninguno** quedó a medias. `order_items` tiene exactamente 368 456 filas (el doble justo) y la consulta que busca pedidos con un número de ítems distinto de 2 devuelve 0. El detalle está en [`evidencias/resultados/analisis_errores_1120.txt`](evidencias/resultados/analisis_errores_1120.txt).

## 7. Consumo del sistema

Se muestreó `docker stats` de forma continua durante cada corrida. El promedio y el máximo consideran solo las muestras con la API bajo carga (CPU API > 5 %). El CPU % de `docker stats` es relativo a 1 núcleo (100 % = 1 núcleo completo), y la VM tiene 4. Fuente: [`evidencias/resultados/resources_report.csv`](evidencias/resultados/resources_report.csv), calculado con `scripts/resources.py`. Las capturas de `docker stats` y `htop` de la sección 9 son instantáneas tomadas a mitad de cada corrida.

| Escenario | Usuarios | CPU API % (prom / máx) | RAM API MiB (prom / máx) | CPU DB % (prom / máx) | RAM DB MiB (prom / máx) | Muestras | Observaciones |
|---|---|---|---|---|---|---|---|
| Baja | 10 | 95.1 / 108.9 | 320.0 / 320.5 | 90.1 / 110.3 | 216.1 / 220.7 | 21 | API y base de datos consumen casi lo mismo desde el primer nivel. Entre las dos usan ~1.9 de los 4 núcleos. |
| Media | 50 | 112.7 / 130.1 | 320.3 / 320.6 | 111.3 / 137.2 | 221.3 / 227.2 | 21 | Ambas suben en paralelo, ~2.2 núcleos entre las dos. La RAM de la API no se mueve. |
| Alta | 100 | 123.5 / 139.5 | 365.8 / 379.1 | 115.1 / 128.2 | 229.2 / 233.6 | 20 | ~2.4 núcleos entre las dos. Quedan ~1.6 núcleos libres en la VM: ninguna de las dos está al límite. |
| Estrés | 1120 | 118.6 / 125.8 | 524.4 / 524.9 | 107.1 / 128.6 | 232.9 / 234.2 | 18 | El consumo de CPU **no sube** respecto a 100 usuarios, pese a tener 11 veces más usuarios. La RAM de la API aparece alta, pero no la causó esta corrida: ver la nota de abajo. |

El dato más revelador de esta tabla es la última fila: con 1120 usuarios la CPU de la API y la de la base de datos están igual o por debajo que con 100, y siguen sobrando ~1.6 núcleos en la VM. Un servidor saturado tendría sus núcleos al tope; aquí no es el caso, lo que confirma lo de la sección 6.1.

**Sobre los 524 MiB de la API en el nivel de estrés.** Sería fácil atribuirlos a la carga, pero los datos crudos lo desmienten. En `evidencias/raw/1120_docker_stats.csv` la API ya aparece con **520.5 MiB y 0.24 % de CPU en la primera muestra**, es decir en reposo y antes de que empezara la corrida; durante la carga solo pasó de 520.8 a 524.9 MiB, **+4.4 MiB**. El crecimiento real es anterior: el nivel de 100 usuarios terminó en 378 MiB y entre ese nivel y esta corrida se ejecutaron las trece sondas de la búsqueda de estrés, algunas de hasta 3000 usuarios. Lo que se ve es heap que la JVM reservó entonces y no devolvió al sistema operativo, no memoria consumida por los 1120 usuarios de esta corrida.

## 8. Análisis y observaciones

- **No se encontró el cuello de botella de la API.** El límite que marcan las mediciones es el del reenvío de puertos de colima entre macOS y la VM. Medida por dentro, la API sostiene 7200–8800 req/s con 1500 conexiones concurrentes y cero rechazos, mientras que por fuera no pasa de ~5200 req/s. Cualquier conclusión sobre "dónde satura Spring Boot" quedaría sin respaldo con este montaje.
- **API y base de datos van parejas.** A diferencia de lo que suele pasar con runtimes de un solo hilo, aquí Postgres consume casi tanta CPU como la API (115 % contra 123 % a 100 usuarios). El trabajo está repartido: Tomcat atiende con 200 hilos y Postgres reparte en varios procesos.
- **Meseta de throughput entre 2900 y 5200 req/s**, con el máximo en 50 usuarios (5226.93). A partir de ahí, más usuarios no dan más peticiones por segundo: solo alargan la cola.
- **Latencia creciente con los usuarios.** Como el throughput es aproximadamente constante, la latencia sube con los usuarios (ley de Little): 2 ms con 10, 8 ms con 50, 19 ms con 100 y 337 ms con 1120.
- **Cero errores 5xx en todas las pruebas**, incluidas las sondas de 3000 usuarios. La API nunca devolvió un error propio: o respondió 201, o la conexión no llegó a establecerse.
- **La transacción es sólida bajo estrés.** Ningún pedido quedó a medias entre `orders` y `order_items` en 184 228 pedidos, y la base terminó con más filas que peticiones exitosas, no con menos.
- **Memoria holgada.** La base de datos se mantiene en ~230 MiB en los cuatro niveles. La API va de 320 MiB a 524 MiB a lo largo de la sesión, pero ese crecimiento es heap retenido por la JVM tras las sondas de estrés, no memoria que pida la carga de cada nivel: dentro de una misma corrida la RAM apenas se mueve (+4.4 MiB en la de 1120). Con 3.81 GiB en la VM, la memoria no limitó nada.
- **Posibles mejoras (no implementadas).** Antes de tocar la API tendría sentido quitar el reenvío de puertos de la ecuación: medir desde dentro de la VM, o directamente en una máquina Linux sin virtualización. Solo después valdría la pena mirar el número de hilos de Tomcat o el tamaño del pool de Hikari, que con estas cargas no dieron señales de ser el límite.
- **Limitaciones de la medición.**
  - JMeter corre en el mismo equipo que los contenedores y compite por CPU con ellos, con solo 8 GB para todo y un heap de 2 GB.
  - Docker vive dentro de una VM, no nativo, lo que añade el reenvío de puertos descrito en la sección 6.1.
  - Las capturas de la carga se tomaron a mitad de la corrida (~30 s), así que el Summary Report visible en `pantalla_completa` es parcial; el resultado final es el de `*_summary_report.png`.
  - Cada nivel oficial se corrió una vez. En las sondas se vio variación entre corridas, aunque los niveles frontera se repitieron y resultaron estables.
  - Estas cifras no son comparables de forma directa con las de los compañeros que midieron sobre Linux sin virtualización: el techo que impone el reenvío afecta solo a este montaje.

## 9. Evidencias

Todas las rutas son relativas a esta carpeta. Cada nivel tiene las cinco capturas que exige el enunciado (docker stats de API+DB, htop, Summary Report, Aggregate Report y JMeter ejecutando), más una de pantalla completa que las muestra todas en el mismo instante. Las de pantalla completa estan recortadas al area de trabajo, sin la barra de menus del sistema.

### Baja (10 usuarios)

- [Docker stats](evidencias/capturas/10u_docker_stats.png) · [htop](evidencias/capturas/10u_htop.png) · [JMeter ejecutando](evidencias/capturas/10u_jmeter_ejecutando.png) · [Summary Report](evidencias/capturas/10u_summary_report.png) · [Aggregate Report](evidencias/capturas/10u_aggregate_report.png) · [Pantalla completa](evidencias/capturas/10u_pantalla_completa.png)

![10 usuarios - docker_stats](evidencias/capturas/10u_docker_stats.png)

![10 usuarios - htop](evidencias/capturas/10u_htop.png)

![10 usuarios - jmeter_ejecutando](evidencias/capturas/10u_jmeter_ejecutando.png)

![10 usuarios - summary_report](evidencias/capturas/10u_summary_report.png)

![10 usuarios - aggregate_report](evidencias/capturas/10u_aggregate_report.png)

![10 usuarios - pantalla_completa](evidencias/capturas/10u_pantalla_completa.png)

### Media (50 usuarios)

- [Docker stats](evidencias/capturas/50u_docker_stats.png) · [htop](evidencias/capturas/50u_htop.png) · [JMeter ejecutando](evidencias/capturas/50u_jmeter_ejecutando.png) · [Summary Report](evidencias/capturas/50u_summary_report.png) · [Aggregate Report](evidencias/capturas/50u_aggregate_report.png) · [Pantalla completa](evidencias/capturas/50u_pantalla_completa.png)

![50 usuarios - docker_stats](evidencias/capturas/50u_docker_stats.png)

![50 usuarios - htop](evidencias/capturas/50u_htop.png)

![50 usuarios - jmeter_ejecutando](evidencias/capturas/50u_jmeter_ejecutando.png)

![50 usuarios - summary_report](evidencias/capturas/50u_summary_report.png)

![50 usuarios - aggregate_report](evidencias/capturas/50u_aggregate_report.png)

![50 usuarios - pantalla_completa](evidencias/capturas/50u_pantalla_completa.png)

### Alta (100 usuarios)

- [Docker stats](evidencias/capturas/100u_docker_stats.png) · [htop](evidencias/capturas/100u_htop.png) · [JMeter ejecutando](evidencias/capturas/100u_jmeter_ejecutando.png) · [Summary Report](evidencias/capturas/100u_summary_report.png) · [Aggregate Report](evidencias/capturas/100u_aggregate_report.png) · [Pantalla completa](evidencias/capturas/100u_pantalla_completa.png)

![100 usuarios - docker_stats](evidencias/capturas/100u_docker_stats.png)

![100 usuarios - htop](evidencias/capturas/100u_htop.png)

![100 usuarios - jmeter_ejecutando](evidencias/capturas/100u_jmeter_ejecutando.png)

![100 usuarios - summary_report](evidencias/capturas/100u_summary_report.png)

![100 usuarios - aggregate_report](evidencias/capturas/100u_aggregate_report.png)

![100 usuarios - pantalla_completa](evidencias/capturas/100u_pantalla_completa.png)

### Estrés (1120 usuarios)

- [Docker stats](evidencias/capturas/1120u_docker_stats.png) · [htop](evidencias/capturas/1120u_htop.png) · [JMeter ejecutando](evidencias/capturas/1120u_jmeter_ejecutando.png) · [Summary Report](evidencias/capturas/1120u_summary_report.png) · [Aggregate Report](evidencias/capturas/1120u_aggregate_report.png) · [Pantalla completa](evidencias/capturas/1120u_pantalla_completa.png)

![1120 usuarios - docker_stats](evidencias/capturas/1120u_docker_stats.png)

![1120 usuarios - htop](evidencias/capturas/1120u_htop.png)

![1120 usuarios - jmeter_ejecutando](evidencias/capturas/1120u_jmeter_ejecutando.png)

![1120 usuarios - summary_report](evidencias/capturas/1120u_summary_report.png)

![1120 usuarios - aggregate_report](evidencias/capturas/1120u_aggregate_report.png)

![1120 usuarios - pantalla_completa](evidencias/capturas/1120u_pantalla_completa.png)

### Contenedores en ejecución

[docker ps](evidencias/capturas/docker_ps.png)

![docker ps](evidencias/capturas/docker_ps.png)

## 10. Fila para la tabla comparativa grupal

| Stack | Baja (10) Avg / P95 / Thr / %Err | Media (50) Avg / P95 / Thr / %Err | Alta (100) Avg / P95 / Thr / %Err | Estrés (1120) Avg / P95 / Thr / %Err |
|---|---|---|---|---|
| Spring Boot (Java) | 2 ms / 3 ms / 4491.69 req/s / 0.00 % | 8 ms / 16 ms / 5226.93 req/s / 0.00 % | 19 ms / 48 ms / 4683.21 req/s / 0.00 % | 337 ms / 563 ms / 2956.36 req/s / 0.19 % |

Al comparar esta fila con la de los demás stacks hay que tener en cuenta lo de la sección 6.1: estas cifras están limitadas por el reenvío de puertos de colima en macOS, no por la API, que medida sin ese intermediario sostiene entre 7200 y 8800 req/s.
