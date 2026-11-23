#!/usr/bin/env python3
"""Read BLB benchmark JSON results and emit a LaTeX table."""
import json
import sys
from pathlib import Path

def load_results(results_dir):
    results = []
    for p in sorted(Path(results_dir).glob("*.json")):
        with open(p) as f:
            results.append(json.load(f))
    return results

def emit_latex(results):
    print(r"\begin{table}[t]")
    print(r"  \centering")
    print(r"  \caption{BLB microbenchmark results (CPU, single-machine two-party).}")
    print(r"  \label{tab:blb-microbenchmarks}")
    print(r"  \begin{tabular}{lrrr}")
    print(r"    \toprule")
    print(r"    \textbf{Test} & \textbf{Time (ms)} & \textbf{Comm.\ Server (B)} & \textbf{Comm.\ Client (B)} \\")
    print(r"    \midrule")
    for r in results:
        name = r["test"].replace("_", r"\_")
        t = r["wall_time_ms"]
        c = r["comm_bytes"]
        time_str = f"${t['mean']:.1f} \\pm {t['std']:.1f}$"
        print(f"    {name} & {time_str} & {c['server_sent']:,} & {c['client_sent']:,} \\\\")
    print(r"    \bottomrule")
    print(r"  \end{tabular}")
    print(r"\end{table}")

if __name__ == "__main__":
    d = sys.argv[1] if len(sys.argv) > 1 else "/blb/results"
    results = load_results(d)
    if not results:
        print(f"No JSON files found in {d}", file=sys.stderr)
        sys.exit(1)
    emit_latex(results)
