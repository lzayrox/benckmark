# Comparativa Grupal y Conclusiones del Taller de Benchmarking

**Taller:** Benchmarking de APIs con PostgreSQL usando Apache JMeter  
**Repositorio grupal:** `https://github.com/lzayrox/benckmark`  
**Fecha:** 20 de noviembre de 2026  

---

## 1. Integrantes del Grupo y Distribución de Stacks

En cumplimiento del enunciado oficial del taller ("Trabajo en grupo de estudiantes, pero cada integrante trabaja en su propio computador, con su propio proyecto y su propio docker-compose"), la distribución de responsabilidades y stacks fue la siguiente:

| Integrante | Stack Evaluado | Entorno de Ejecución | Carpeta en Repositorio | Estado |
|---|---|---|---|---|
| **Rafael Potes** | **Node.js 22 + NestJS 10** + PostgreSQL 16 | Windows 11 Pro, AMD Ryzen 5 8640HS (12 hilos, 36 GB RAM), WSL2 + Docker Desktop | `entrega-rafael-potes-node/` | Entregado (PR #1 fusionado) |
| **Orlando Palma** | **Java 21 + Spring Boot 3.4** + PostgreSQL 16 | macOS Ventura, Apple M1 (8 núcleos, 8 GB RAM), Docker sobre colima VM (4 vCPU, 3.8 GiB) | `entrega-orlando-palma-java/` | Entregado (PR #3 fusionado) |
| **Humberto Llinás** | **Go 1.23 (net/http + pgx)** + PostgreSQL 16 | Linux nativo | `docs/go/` | Entregado (datos iniciales) |
| **Humberto Llinás** | **Python 3.12 (Flask + Gunicorn)** + PostgreSQL 16 | Linux nativo | `docs/python/` | Entregado (datos iniciales) |

Cada microservicio implementó el endpoint obligatorio `POST /api/orders` con transacción ACID contra PostgreSQL 16, insertando cabecera en `orders` y detalle en `order_items`, calculando `totalAmount` e `itemsCount` y retornando HTTP 201 con `orderId`, totales y `processedAt`.

---

## 2. Tabla Comparativa Única Consolidada

La siguiente tabla consolida los resultados obtenidos por los 4 stacks bajo los tres escenarios estándar (Baja: 10 usuarios, Media: 50 usuarios, Alta: 100 usuarios) y el escenario de **Estrés / Máxima Carga** alcanzado por cada tecnología.

Todas las corridas oficiales se ejecutaron durante **60 segundos** con **10 segundos de rampa (ramp-up)** a través de Apache JMeter.

| Stack | Métrica | Baja carga (10 usuarios) | Media carga (50 usuarios) | Alta carga (100 usuarios) | Estrés / Carga Máxima |
|---|---|---|---|---|---|
| **Node.js (NestJS)**<br>*(Rafael Potes)* | **Avg (ms)**<br>**P95 (ms)**<br>**Throughput (req/s)**<br>**% Error** | 14 ms<br>27 ms<br>634.43 req/s<br>**0.00 %** | 62 ms<br>84 ms<br>731.03 req/s<br>**0.00 %** | 125 ms<br>163 ms<br>727.54 req/s<br>**0.00 %** | *(1500 usuarios)*<br>2025 ms<br>2783 ms<br>663.01 req/s<br>**0.80 %** *(timeouts cliente)* |
| **Java (Spring Boot)**<br>*(Orlando Palma)* | **Avg (ms)**<br>**P95 (ms)**<br>**Throughput (req/s)**<br>**% Error** | 2 ms<br>3 ms<br>4491.69 req/s<br>**0.00 %** | 8 ms<br>16 ms<br>5226.93 req/s<br>**0.00 %** | 19 ms<br>48 ms<br>4683.21 req/s<br>**0.00 %** | *(1120 usuarios)*<br>337 ms<br>563 ms<br>2956.36 req/s<br>**0.19 %** *(refusal de colima)* |
| **Go (net/http + pgx)**<br>*(Humberto Llinás)* | **Avg (ms)**<br>**P95 (ms)**<br>**Throughput (req/s)**<br>**% Error** | < 1 ms *(0 ms)*<br>1 ms<br>9687.30 req/s<br>**0.00 %** | 1 ms<br>2 ms<br>28433.10 req/s<br>**0.00 %** | 2 ms<br>4 ms<br>4426.88 req/s\*<br>**0.00 %** | *(500 usuarios)*<br>13 ms<br>20 ms<br>18969.14 req/s<br>**0.00 %** |
| **Python (Flask + Gunicorn)**<br>*(Humberto Llinás)* | **Avg (ms)**<br>**P95 (ms)**<br>**Throughput (req/s)**<br>**% Error** | 1 ms<br>3 ms<br>4864.85 req/s<br>**0.00 %** | 7 ms<br>11 ms<br>6251.37 req/s<br>**0.00 %** | 15 ms<br>20 ms<br>6232.49 req/s<br>**0.00 %** | *(500 usuarios)*<br>85 ms<br>105 ms<br>5579.21 req/s<br>**0.00 %** |

*\*Nota metodológica sobre Go a 100 usuarios:* El archivo `100_aggregate.csv` de Go acumuló muestras en el listener de la GUI durante 776 segundos (3,436,072 muestras), lo que distorsionó el Throughput instantáneo en ese archivo específico a 4,426 req/s; sin embargo, las pruebas a 120, 140 y 160 usuarios demuestran que Go sostuvo de manera estable **~28,950 req/s** con latencias P95 entre 5 y 6 ms.

---

## 3. Consumo de Recursos del Sistema

Monitoreo promedio extraído mediante `docker stats` sobre el contenedor de la API y el contenedor de la base de datos PostgreSQL (`postgres:16`) durante las corridas de carga:

| Stack | Escenario | CPU API (%) | RAM API (MiB) | CPU DB (%) | RAM DB (MiB) | Observaciones de Comportamiento |
|---|---|---|---|---|---|---|
| **Node.js (NestJS)** | **Baja (10u)**<br>**Media (50u)**<br>**Alta (100u)**<br>**Estrés (1500u)** | 96.4 %<br>102.0 %<br>105.5 %<br>106.5 % | 66.4 MiB<br>104.8 MiB<br>99.3 MiB<br>160.2 MiB | 59.6 %<br>72.5 %<br>72.2 %<br>67.4 % | 94.8 MiB<br>135.2 MiB<br>139.7 MiB<br>142.9 MiB | Monohilo saturado al 100% de un núcleo. Consumo de RAM moderado (<161 MiB). La base de datos nunca se saturó (máx 72% CPU). A 1500u se encolan peticiones causando timeouts. |
| **Java (Spring Boot)** | **Baja (10u)**<br>**Media (50u)**<br>**Alta (100u)**<br>**Estrés (1120u)** | 95.1 %<br>112.7 %<br>123.5 %<br>118.6 % | 320.0 MiB<br>320.3 MiB<br>365.8 MiB<br>524.4 MiB | 90.1 %<br>111.3 %<br>115.1 %<br>107.1 % | 216.1 MiB<br>221.3 MiB<br>229.2 MiB<br>232.9 MiB | Multihilo eficiente (Tomcat + HikariCP 30). Uso de RAM propio de JVM (arranca en ~320 MiB y sube a 524 MiB en estrés). CPU compartida en VM de 4 núcleos. |
| **Go (net/http + pgx)** | **Baja (10u)**<br>**Media (50u)**<br>**Alta (100u)**<br>**Estrés (500u)** | 102.8 %<br>235.8 %<br>229.4 %<br>251.7 % | 21.6 MiB<br>28.2 MiB<br>30.4 MiB<br>42.4 MiB | 83.4 %<br>217.9 %<br>210.2 %<br>221.4 % | 214.9 MiB<br>277.5 MiB<br>279.9 MiB<br>283.1 MiB | Eficiencia de recursos excepcional. Consumo de memoria mínimo (<43 MiB en máxima carga). Go y Postgres escalan aprovechando múltiples núcleos (>220% CPU). |
| **Python (Flask + Gunicorn)** | **Baja (10u)**<br>**Media (50u)**<br>**Alta (100u)**<br>**Estrés (500u)** | *No reg.\**<br>*No reg.\**<br>*No reg.\**<br>*No reg.\** | *No reg.\**<br>*No reg.\**<br>*No reg.\**<br>*No reg.\** | *No reg.\**<br>*No reg.\**<br>*No reg.\**<br>*No reg.\** | *No reg.\**<br>*No reg.\**<br>*No reg.\**<br>*No reg.\** | El autor del stack no registró el archivo `resources_report.csv` para Python (solo para Go). La evidencia en `docker_ps.png` y JMeter valida 4 workers Gunicorn con 4 threads. |

*\*Nota sobre Python:* El autor de la prueba ejecutó bajo Linux y adjuntó las métricas de JMeter (`*_aggregate.csv`, `*_summary.csv`), `prueba.png` y `docker_ps.png`, pero no conservó el log de muestreo continuo de `docker stats`.

---

## 4. Respuestas a las 8 Conclusiones del Enunciado

### Eje 1: Rendimiento

#### 1. ¿Cuál stack tuvo mejor latencia promedio?
**Go (net/http + pgx)** obtuvo la mejor latencia promedio en todos los escenarios evaluados:
- A 10 usuarios: **0 ms** (< 1 ms), frente a 1 ms de Python, 2 ms de Java y 14 ms de Node.js.
- A 50 usuarios: **1 ms**, frente a 7 ms de Python, 8 ms de Java y 62 ms de Node.js.
- A 100 usuarios: **2 ms**, frente a 15 ms de Python, 19 ms de Java y 125 ms de Node.js.
- En carga extrema: **13 ms** (a 500 usuarios), superando a Java (337 ms a 1120u), Python (85 ms a 500u) y Node.js (2025 ms a 1500u).

La combinación de código compilado a binario nativo, goroutines ligeras y el uso de `pgx.Batch` (que reduce los viajes de ida y vuelta a PostgreSQL enviando las inserciones en un único paquete) colocó a Go como el líder indiscutible en velocidad de respuesta.

#### 2. ¿Cuál mantuvo el mejor throughput en cargas altas?
**Go mantuvo el mayor throughput con amplia ventaja:**
- Sostuvo tasas sostenidas de **28,433 req/s** a 50 usuarios y **29,007 req/s** a 140 usuarios.
- En segundo lugar se ubicó **Python (Flask + Gunicorn)** con un throughput notablemente constante de **~6,200 req/s** (6,251 req/s a 50u, 6,232 req/s a 100u y 5,579 req/s a 500u).
- En tercer lugar **Java (Spring Boot)** con **5,226 req/s** a 50u y **4,683 req/s** a 100u (afectado por la capa de reenvío de la máquina virtual colima en macOS).
- **Node.js (NestJS)** quedó en último lugar con un techo de **~730 req/s** debido al estrangulamiento del hilo único del event loop.

#### 3. ¿Qué lenguaje fue más estable?
**Go y Python demostraron la mayor estabilidad:**
- Ambos registraron **0.00 % de error** en todas sus corridas desde 10 hasta 500 usuarios concurrentes.
- En consistencia de percentiles, **Go fue el más estable**, manteniendo un P95 de tan solo **4 ms a 100 usuarios** y **20 ms a 500 usuarios**.
- Python también mostró una estabilidad impecable, con un P95 que pasó de 3 ms (10u) a 20 ms (100u) y 105 ms (500u) sin un solo descarte ni timeout.
- Java fue sumamente estable hasta 100 usuarios (P95 de 48 ms), pero por encima de 1000 usuarios la virtualización de red de colima desestabilizó la conexión.
- Node.js presentó una degradación lineal pronunciada conforme creció la concurrencia: el P95 se cuadruplicó entre 10u (27 ms) y 50u (84 ms), se duplicó de nuevo a 100u (163 ms) y llegó a 2,783 ms en estrés.

---

### Eje 2: Eficiencia

#### 4. ¿Algún stack mostró errores bajo alta carga?
**Sí, dos de los cuatro stacks presentaron errores al superar los 1,000 usuarios concurrentes:**
1. **Node.js (NestJS):** a **1500 usuarios concurrentes**, registró un **0.80 % de error** (336 solicitudes fallidas de un total de 42,117 transacciones enviadas en 60 segundos).
2. **Java (Spring Boot):** a **1120 usuarios concurrentes**, registró un **0.19 % de error** (354 conexiones rechazadas de un total de 184,477 peticiones enviadas).
3. **Go y Python:** se probaron hasta 500 usuarios concurrentes y registraron **0.00 % de error** (cero fallos).

#### 5. ¿Qué puede explicar esas fallas?
El análisis técnico de las fallas revela causas arquitectónicas y de infraestructura completamente diferentes:

1. **Causa en Node.js (NestJS) — Saturación del Event Loop monohilo:**
   - La totalidad de los 336 errores fueron de tipo `java.net.SocketTimeoutException: Read timed out` (configurado en 10 segundos en JMeter).
   - **No hubo un solo error HTTP 5xx ni fallo de PostgreSQL:** la base de datos procesó y guardó con integridad las 41,781 órdenes exitosas.
   - La causa raíz radica en que Node.js ejecuta JavaScript en un único hilo (`single-threaded event loop`). Aunque las operaciones de socket hacia PostgreSQL son no bloqueantes, el trabajo síncrono en CPU (validaciones de clase en NestJS, serialización/deserialización de JSON y cálculo de totales) consumió el **100 % de un núcleo de CPU** (106.5 % en docker stats).
   - A 1500 hilos concurrentes, las peticiones entrantes formaron una cola en el event loop que superó los 10 segundos de tiempo de espera antes de ser atendidas, provocando que el cliente cerrara el socket por timeout.

2. **Causa en Java (Spring Boot) — Cuello de botella en la capa de reenvío de puertos (macOS / colima):**
   - Los 354 errores en Java correspondieron a `org.apache.http.conn.HttpHostConnectException: Connect to localhost:5002 failed: Connection refused`.
   - **No hubo fallos en la JVM, ni presión de Garbage Collector (GC), ni agotamiento del pool HikariCP:** el contenedor de PostgreSQL terminó con 184,228 pedidos almacenados (más que los 184,123 que el cliente JMeter contó como exitosos), demostrando que la API procesó transaccionalmente todas las solicitudes que llegaron a su socket.
   - La falla se debió al puente de red de Docker en macOS (`colima` con `Virtualization.Framework`), donde el reenvío de puertos host-hacia-VM (`gvisor-tap-vsock`) saturó el backlog de conexiones TCP (`somaxconn` a nivel de sistema operativo de la VM) ante la ráfaga de 1120 sockets simultáneos. Pruebas directas con `ab` dentro de la VM confirmaron que la API atiende 1500 usuarios sin un solo error.

---

### Eje 3: Recomendación para Producción

#### 6. ¿Cuál stack recomendarían para una empresa que requiere alto desempeño?
**Recomendación principal: Go (net/http + pgx)**.
- **Rendimiento:** Procesa más de 28,000 req/s con latencias sub-milisegundo (P95 de 4 ms a 100 usuarios concurrentes).
- **Eficiencia de costos en la nube:** Consume únicamente **~30 MiB de memoria RAM** bajo alta carga, en contraste con los ~365-524 MiB de Java o los ~160 MiB de Node.js. Esto permite desplegar 10 contenedores de Go en la misma memoria que requeriría una sola instancia de Spring Boot, reduciendo drásticamente la factura de infraestructura.
- **Concurrencia nativa:** El modelo de `goroutines` (hilos en espacio de usuario de 2 KB) gestiona miles de conexiones sin el overhead de hilos de sistema operativo ni la limitación monohilo de Node.

*Alternativa corporativa:* Si la organización cuenta con una base instalada de Java y estándares corporativos maduros, **Java 21 con Spring Boot 3** es una opción de primer nivel: alcanzó ~5,200 req/s con excelente robustez transaccional y pooling de alto rendimiento (`HikariCP`).

#### 7. ¿Cuál stack es más fácil de implementar pero sacrifica rendimiento?
**Node.js con NestJS**.
- **Facilidad de desarrollo:** Ofrece la experiencia de desarrollo (DX) más estructurada y productiva del grupo gracias a TypeScript, inyección de dependencias modular, decoradores limpios y validación automática mediante DTOs.
- **Sacrificio de rendimiento:** Su arquitectura estándar monohilo impone un techo temprano de rendimiento (~730 req/s en esta prueba), rindiendo **7.5 veces menos que Java** y **38 veces menos que Go** en la misma máquina. Para llevarlo a producción de alto volumen se requiere obligatoriamente implementar arquitectura de clúster (`pm2`, réplicas horizontales en Kubernetes y balanceadores de carga como NGINX/Envoy) para no desperdiciar los demás núcleos del CPU.

#### 8. ¿Cuál stack ofrece un mejor balance entre sencillez y velocidad?
**Python (Flask + Gunicorn con workers asíncronos/hilos)**.
- **Sencillez:** El microservicio completo se implementó en apenas **50 líneas de código limpio**, sin configuración compleja, sin compilación previa y con una curva de aprendizaje mínima para cualquier ingeniero.
- **Velocidad:** A pesar de la reputación tradicional de Python como lenguaje lento, el despliegue con Gunicorn (4 workers multi-hilo) y el pool de conexiones `psycopg_pool` alcanzó **más de 6,200 req/s sostenidos** con latencias de 15 ms a 100 usuarios, superando a Node.js por un factor de 8.5 y ofreciendo un rendimiento equiparable a Java sin la complejidad sintáctica ni el consumo de memoria de la JVM.

*(Nota complementaria: Si el equipo de desarrollo domina Go, Go representa el balance técnico supremo, uniendo simplicidad conceptual de sintaxis con velocidad casi de lenguaje C).*

---

## 5. Limitaciones Metodológicas del Estudio

Para una lectura rigurosa de los resultados consolidados, deben considerarse las siguientes limitaciones inherentes al entorno distribuido de trabajo:

1. **Heterogeneidad de hardware y sistemas operativos:**
   - Cada integrante ejecutó las pruebas en su computador personal:
     - Node.js corrió en Windows 11 con procesador AMD Ryzen 5 8640HS (12 hilos, 36 GB RAM) sobre WSL2.
     - Java corrió en macOS con procesador Apple Silicon M1 (8 núcleos, 8 GB RAM) sobre Docker en colima VM.
     - Go y Python corrieron en Linux nativo.
   - Las diferencias de rendimiento reflejan no solo la velocidad intrínseca del lenguaje, sino también las discrepancias de IPC del CPU, velocidad de memoria y sistema de archivos.

2. **Impacto de la virtualización de red:**
   - En macOS, Docker no corre de forma nativa sino dentro de una máquina virtual Linux. El reenvío de puertos desde el host generó cuellos de botella artificiales en Java a cargas extremas (>1,000 usuarios) que no existen en despliegues reales sobre servidores Linux de producción.

3. **Competición de recursos Host vs Cliente:**
   - En todos los casos, el generador de carga (Apache JMeter en modo GUI) corrió en la misma máquina física que la base de datos y la API. El cliente JMeter consumió CPU y memoria en paralelo con los contenedores bajo prueba.

4. **Acumulación de muestras en listeners de JMeter:**
   - En el caso particular de Go a 100 usuarios, el archivo CSV de Aggregate Report acumuló peticiones de pruebas anteriores, distorsionando el cálculo de throughput sobre la ventana temporal. Las mediciones a 50, 120, 140 y 160 usuarios sirvieron como referencia no viciada del throughput real de Go.
