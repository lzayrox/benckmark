#!/usr/bin/env python3
import argparse
import csv
import gzip
import json
import math
import os
import statistics
import sys
from collections import Counter

LABEL = "POST /api/orders"
SUMMARY_HEADER = [
    "Label", "# Samples", "Average", "Min", "Max", "Std. Dev.", "Error %",
    "Throughput", "Received KB/sec", "Sent KB/sec", "Avg. Bytes",
]
AGGREGATE_HEADER = [
    "Label", "# Samples", "Average", "Median", "90% Line", "95% Line", "99% Line",
    "Min", "Max", "Error %", "Throughput", "Received KB/sec", "Sent KB/sec",
]


def fail(message):
    print(f"Error: {message}", file=sys.stderr)
    sys.exit(1)


def parse_num(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def open_jtl(path):
    """Abre el JTL, comprimido con gzip o sin comprimir.

    Los JTL de las corridas oficiales se versionan comprimidos porque en crudo
    ocupan decenas de MB cada uno.
    """
    if path.endswith(".gz"):
        return gzip.open(path, mode="rt", newline="", encoding="utf-8", errors="replace")
    return open(path, newline="", encoding="utf-8", errors="replace")


def read_samples(path):
    with open_jtl(path) as fh:
        return [row for row in csv.DictReader(fh) if row.get("label") == LABEL]


def classify(code):
    code = code.strip()
    if code.startswith("Non HTTP response code"):
        return "socket"
    if code.isdigit() and 500 <= int(code) <= 599:
        return "5xx"
    return "other"


def percentile(sorted_values, p):
    k = max(1, math.ceil(p / 100 * len(sorted_values)))
    return sorted_values[k - 1]


def compute(rows):
    n = len(rows)
    elapsed = sorted(parse_num(r["elapsed"]) for r in rows)
    start = min(parse_num(r["timeStamp"]) for r in rows)
    end = max(parse_num(r["timeStamp"]) + parse_num(r["elapsed"]) for r in rows)
    span_s = max(end - start, 1.0) / 1000
    received = sum(parse_num(r["bytes"]) for r in rows)
    sent = sum(parse_num(r["sentBytes"]) for r in rows)
    average = sum(elapsed) / n

    failed = [r for r in rows if r["success"].strip().lower() != "true"]
    kinds = Counter(classify(r["responseCode"]) for r in failed)
    messages = Counter(f"{r['responseCode']}: {r['responseMessage']}" for r in failed)
    top_error = ""
    if messages:
        top_error = sorted(messages.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]

    return {
        "samples": n,
        "average": average,
        "median": percentile(elapsed, 50),
        "p90": percentile(elapsed, 90),
        "p95": percentile(elapsed, 95),
        "p99": percentile(elapsed, 99),
        "min": elapsed[0],
        "max": elapsed[-1],
        "std": statistics.pstdev(elapsed),
        "error_pct": len(failed) / n * 100,
        "throughput": n / span_s,
        "received_kbs": received / 1024 / span_s,
        "sent_kbs": sent / 1024 / span_s,
        "avg_bytes": received / n,
        "errors_5xx": kinds["5xx"],
        "errors_socket": kinds["socket"],
        "errors_other": kinds["other"],
        "top_error": top_error,
    }


def write_csv(path, header, rows):
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.writer(fh, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def summary_row(label, st):
    return [
        label, st["samples"], int(st["average"]), round(st["min"]), round(st["max"]),
        f"{st['std']:.2f}", f"{st['error_pct']:.2f}%", f"{st['throughput']:.2f}",
        f"{st['received_kbs']:.2f}", f"{st['sent_kbs']:.2f}", f"{st['avg_bytes']:.1f}",
    ]


def aggregate_row(label, st):
    return [
        label, st["samples"], int(st["average"]), round(st["median"]),
        round(st["p90"]), round(st["p95"]), round(st["p99"]),
        round(st["min"]), round(st["max"]), f"{st['error_pct']:.2f}%",
        f"{st['throughput']:.2f}", f"{st['received_kbs']:.2f}", f"{st['sent_kbs']:.2f}",
    ]


def main(argv=None):
    parser = argparse.ArgumentParser(description="Estadisticas de un JTL de JMeter para POST /api/orders.")
    parser.add_argument("jtl")
    parser.add_argument("--summary")
    parser.add_argument("--aggregate")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    if not os.path.isfile(args.jtl):
        fail(f"no existe el archivo JTL: {args.jtl}")
    try:
        rows = read_samples(args.jtl)
    except (OSError, csv.Error) as exc:
        fail(f"no se pudo leer {args.jtl}: {exc}")
    except KeyError as exc:
        fail(f"{args.jtl} no tiene la columna {exc}")
    if not rows:
        fail(f"no hay muestras de '{LABEL}' en {args.jtl}")

    try:
        st = compute(rows)
    except KeyError as exc:
        fail(f"{args.jtl} no tiene la columna {exc}")
    if args.summary:
        write_csv(args.summary, SUMMARY_HEADER, [summary_row(LABEL, st), summary_row("TOTAL", st)])
    if args.aggregate:
        write_csv(args.aggregate, AGGREGATE_HEADER, [aggregate_row(LABEL, st), aggregate_row("TOTAL", st)])

    if args.json:
        result = {
            "samples": st["samples"],
            "avg": int(st["average"]),
            "p90": round(st["p90"]),
            "p95": round(st["p95"]),
            "throughput": round(st["throughput"], 2),
            "error_pct": round(st["error_pct"], 2),
            "errors_5xx": st["errors_5xx"],
            "errors_socket": st["errors_socket"],
            "errors_other": st["errors_other"],
            "top_error": st["top_error"],
        }
        print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
