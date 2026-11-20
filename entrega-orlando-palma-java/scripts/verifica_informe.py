"""Comprueba que las cifras del INFORME coinciden con los CSV generados.

Recorre las cuatro tablas del informe (escenarios, consumo, sondas de estres y
fila grupal) y las contrasta celda a celda con los archivos de evidencias/.
Ademas comprueba que todos los enlaces a evidencias/ existen en disco.

Se ejecuta desde la raiz de la entrega:

    python3 scripts/verifica_informe.py

Devuelve codigo 1 si encuentra cualquier discrepancia.
"""
import csv, pathlib, re, sys

inf = pathlib.Path("INFORME.md").read_text(encoding="utf-8").splitlines()
fallos = []
NOMBRES = {10: "Baja", 50: "Media", 100: "Alta", 1120: "Estrés"}

def filas(n_cols, primera):
    return [[c.strip() for c in l.strip().strip("|").split("|")]
            for l in inf if l.startswith(f"| {primera} |")
            and len([c for c in l.strip().strip("|").split("|")]) == n_cols]

def agg(u):
    return list(csv.DictReader(open(f"evidencias/resultados/{u}u_aggregate.csv")))[0]

def num(s):
    # se ignoran anotaciones entre parentesis, como "1100 (1.a)"
    s = re.sub(r"\s*\([^)]*\)", "", s)
    return "".join(ch for ch in s if not ch.isspace())

# --- tabla de escenarios: 12 columnas ---
for u, nombre in NOMBRES.items():
    f = filas(12, nombre)
    if not f:
        fallos.append(f"escenario {nombre}: fila no encontrada"); continue
    f = f[0]
    r = agg(u)
    esperado = [nombre, str(u), r["# Samples"], r["Average"], r["90% Line"], r["95% Line"],
                r["99% Line"], r["Min"], r["Max"], r["Throughput"], "0.00" if r["Error %"]=="0.00%" else r["Error %"].rstrip("%")]
    for i, e in enumerate(esperado):
        if num(f[i]) != num(e):
            fallos.append(f"escenario {nombre}, columna {i+1}: informe '{f[i]}' vs csv '{e}'")

# --- tabla de consumo: 8 columnas ---
rec = {r["Users"]: r for r in csv.DictReader(open("evidencias/resultados/resources_report.csv"))}
for u, nombre in NOMBRES.items():
    f = filas(8, nombre)
    if not f:
        fallos.append(f"consumo {nombre}: fila no encontrada"); continue
    f = f[0]; r = rec[str(u)]
    pares = [(f[2], r["API_CPU_avg_%"], r["API_CPU_max_%"]),
             (f[3], r["API_Mem_avg_MiB"], r["API_Mem_max_MiB"]),
             (f[4], r["DB_CPU_avg_%"], r["DB_CPU_max_%"]),
             (f[5], r["DB_Mem_avg_MiB"], r["DB_Mem_max_MiB"])]
    for celda, a, b in pares:
        if num(celda) != num(f"{a} / {b}"):
            fallos.append(f"consumo {nombre}: informe '{celda}' vs csv '{a} / {b}'")
    if num(f[6]) != num(r["muestras"]):
        fallos.append(f"consumo {nombre}: muestras informe '{f[6]}' vs csv '{r['muestras']}'")

# --- tabla de sondas: 10 columnas, primera celda = indice ---
sondas = list(csv.DictReader(open("evidencias/busqueda_estres/busqueda_estres.csv")))
for i, s in enumerate(sondas, 1):
    f = filas(10, i)
    if not f:
        fallos.append(f"sonda {i}: fila no encontrada"); continue
    f = f[0]
    esperado = [str(i), s["users"], s["samples"], s["avg_ms"], s["p90_ms"], s["p95_ms"],
                s["throughput"], f"{float(s['error_pct']):.2f}", s["errors_5xx"], s["errors_socket"]]
    for j, e in enumerate(esperado):
        if num(f[j]) != num(e):
            fallos.append(f"sonda {i} ({s['users']}u), columna {j+1}: informe '{f[j]}' vs csv '{e}'")

# --- tabla grupal ---
g = [l for l in inf if l.startswith("| Spring Boot (Java)")]
if not g:
    fallos.append("tabla grupal: fila no encontrada")
else:
    celdas = [c.strip() for c in g[0].strip().strip("|").split("|")][1:]
    for celda, u in zip(celdas, (10, 50, 100, 1120)):
        r = agg(u)
        for valor in (r["Average"], r["95% Line"], r["Throughput"]):
            if valor not in celda:
                fallos.append(f"tabla grupal {u}u: falta '{valor}' en '{celda}'")

# --- enlaces a imagenes ---
import re
for m in re.finditer(r"\]\((evidencias/[^)]+)\)", "\n".join(inf)):
    destino = pathlib.Path(m.group(1))
    if not destino.exists():          # vale tanto archivo como carpeta
        fallos.append(f"enlace roto: {m.group(1)}")

print(f"sondas verificadas: {len(sondas)}  |  escenarios: {len(NOMBRES)}")
if fallos:
    print("\nDISCREPANCIAS:")
    for f in fallos: print("  -", f)
    sys.exit(1)
print("\nTodas las cifras del INFORME coinciden con los CSV, y todos los enlaces existen.")
