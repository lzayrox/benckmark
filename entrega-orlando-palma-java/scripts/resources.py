"""Resume los muestreos de docker stats de cada corrida en resources_report.csv.

Solo se promedian las muestras tomadas con la API bajo carga (CPU de la API > 5 %),
para no mezclar los segundos de reposo antes y despues de la prueba.

Uso: python3 scripts/resources.py evidencias/raw evidencias/resultados/resources_report.csv
"""
import csv
import re
import sys
from pathlib import Path

API = "java-api-orders"
DB = "java-db-orders"

UNITS = {"B": 1 / 1048576, "KiB": 1 / 1024, "KB": 1 / 1024, "MiB": 1, "MB": 1, "GiB": 1024, "GB": 1024}


def mem_mib(text):
    m = re.match(r"\s*([\d.]+)\s*([A-Za-z]+)", text.split("/")[0])
    return float(m.group(1)) * UNITS[m.group(2)]


def summarize(path):
    rows = {}
    with open(path, newline="", encoding="utf-8-sig") as f:
        for r in csv.DictReader(f):
            if not r.get("cpu"):
                continue
            rows.setdefault(r["ts"], {})[r["name"]] = (float(r["cpu"].rstrip("%")), mem_mib(r["mem"]))
    load = [v for v in rows.values() if API in v and DB in v and v[API][0] > 5]
    if not load:
        return None

    def stats(name, idx):
        vals = [v[name][idx] for v in load]
        return round(sum(vals) / len(vals), 1), round(max(vals), 1)

    return [*stats(API, 0), *stats(API, 1), *stats(DB, 0), *stats(DB, 1), len(load)]


def main(raw_dir, out):
    header = ["Users", "API_CPU_avg_%", "API_CPU_max_%", "API_Mem_avg_MiB", "API_Mem_max_MiB",
              "DB_CPU_avg_%", "DB_CPU_max_%", "DB_Mem_avg_MiB", "DB_Mem_max_MiB", "muestras"]
    lines = []
    for p in sorted(Path(raw_dir).glob("*_docker_stats.csv"), key=lambda p: int(p.name.split("_")[0])):
        s = summarize(p)
        if s:
            lines.append([p.name.split("_")[0], *s])
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(header)
        w.writerows(lines)
    for l in [header, *lines]:
        print(",".join(map(str, l)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
