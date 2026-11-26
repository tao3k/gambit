#!/usr/bin/env python3
"""Modular true-multicore PBT & scaling runner for Gambit SMP (Linux & macOS).

Single source of truth shared between local engineering verification and
GitHub Actions (.github/actions/gambit-multicore-pbt).
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

PBT_O1_TARGETS = [
    ("gambit-lin", "gambit-lin.scm", "GAMBIT-LIN-PASS", None),
    ("gambit-stm", "gambit-stm.scm", "GAMBIT-STM-PASS", None),
    ("c1-weak-will-table", "c1-weak-will-table-smp.scm", "C1-WEAK-WILL-TABLE-PASS", 128.0),
    ("c2-heterogeneous-roots", "c2-heterogeneous-roots-gc-hammer.scm", "C2-HETEROGENEOUS-ROOTS-PASS", 256.0),
    ("c3-ffi-callback-reentry", "c3-ffi-blocking-callback-reentry-smp.scm", "C3-FFI-CALLBACK-REENTRY-PASS", 128.0),
    ("c4-dynamic-o1-symkey", "c4-dynamic-o1-binding-symkey-race.scm", "C4-DYNAMIC-O1-BINDING-SYMKEY-PASS", 256.0),
    ("c5-multishot-cc", "c5-multishot-cc-cross-core-smp.scm", "C5-MULTISHOT-CC-CROSS-CORE-PASS", 256.0),
    ("c6-parameterize-denv", "c6-parameterize-denv-isolation-smp.scm", "C6-PARAMETERIZE-DENV-ISOLATION-PASS", 256.0),
    ("t1-robustness-hardening", "t1-robustness-hardening-smp.scm", "T1-ROBUSTNESS-HARDENING-PASS", 256.0),
]

SCALING_WORKLOADS = {
    "par_compute_fib": r"""
(declare (standard-bindings) (extended-bindings) (block) (fixnum) (not safe))
(define (fib n)
  (if (< n 2)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))
(define (gc-count)
  (inexact->exact (f64vector-ref (##process-statistics) 6)))
(define (run-par-compute)
  (let* ((gc0 (gc-count))
         (threads
          (let loop ((i 0) (acc '()))
            (if (= i 8)
                acc
                (loop (+ i 1)
                      (cons (thread-start! (make-thread (lambda () (fib 35)))) acc)))))
         (vals (map thread-join! threads))
         (gc1 (gc-count)))
    (for-each (lambda (v) (if (not (= v 9227465)) (error "fib mismatch" v))) vals)
    (println "PAR_COMPUTE_PASS workers=8 fib35=9227465 gcs=" (- gc1 gc0))))
(run-par-compute)
""",
    "par_alloc_gc_m65536": r"""
(declare (standard-bindings) (extended-bindings) (block))
(define (gc-count)
  (inexact->exact (f64vector-ref (##process-statistics) 6)))
(define (churn-worker id iters)
  (let loop ((i 0) (acc 0.0))
    (if (= i iters)
        acc
        (let* ((v (make-f64vector 256 (exact->inexact (+ id (modulo i 17)))))
               (p (list (vector i id v) (cons i (number->string i))))
               (s (+ (f64vector-ref v 0) (f64vector-ref v 255))))
          (loop (+ i 1) (+ acc s (if (pair? p) 1.0 0.0)))))))
(define (run-par-alloc)
  (let* ((gc0 (gc-count))
         (threads
          (let loop ((i 0) (acc '()))
            (if (= i 8)
                acc
                (loop (+ i 1)
                      (cons (thread-start! (make-thread (lambda () (churn-worker i 15000)))) acc)))))
         (vals (map thread-join! threads))
         (gc1 (gc-count)))
    (for-each (lambda (v) (if (not (and (flonum? v) (> v 0.0))) (error "alloc mismatch" v))) vals)
    (println "PAR_ALLOC_GC_PASS workers=8 iters=15000 gcs=" (- gc1 gc0))))
(run-par-alloc)
""",
}

BSD_TIME_RE = re.compile(r"^\s*([0-9.]+)\s+real\s+([0-9.]+)\s+user\s+([0-9.]+)\s+sys\s*$", re.M)
BSD_RSS_RE = re.compile(r"^\s*(\d+)\s+maximum resident set size\s*$", re.M)
GNU_USER_RE = re.compile(r"User time \(seconds\):\s*([0-9.]+)")
GNU_SYS_RE = re.compile(r"System time \(seconds\):\s*([0-9.]+)")
GNU_RSS_RE = re.compile(r"Maximum resident set size \(kbytes\):\s*(\d+)")


def build_env(runtime_dir: Path) -> dict[str, str]:
    env = os.environ.copy()
    if sys.platform == "darwin":
        env["PATH"] = f"/usr/bin:/bin:/opt/homebrew/bin:{env.get('PATH', '')}"
    env.pop("GAMBOPT", None)
    return env


def run_timed(cmd: list[str], cwd: Path, env: dict[str, str], timeout: int) -> dict:
    time_bin = "/usr/bin/time"
    use_bsd = sys.platform == "darwin" and Path(time_bin).is_file()
    use_gnu = sys.platform.startswith("linux") and Path(time_bin).is_file()
    wrapped = ([time_bin, "-l", *cmd] if use_bsd else ([time_bin, "-v", *cmd] if use_gnu else cmd))

    t0 = time.monotonic()
    proc = subprocess.Popen(
        wrapped,
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        wall_s = time.monotonic() - t0
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            out, err = proc.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            out, err = "", ""
        return {
            "exit": 124,
            "realSeconds": round(wall_s, 4),
            "userSeconds": 0.0,
            "sysSeconds": 0.0,
            "cpuSeconds": 0.0,
            "peakRssBytes": 0,
            "peakRssMiB": 0.0,
            "stdout": (out or "").strip(),
            "stderrTail": f"TIMEOUT after {timeout}s\n" + "\n".join((err or "").strip().splitlines()[:6]),
        }
    wall_s = time.monotonic() - t0
    user_s = sys_s = 0.0
    rss_bytes = 0
    if use_bsd:
        if m := BSD_TIME_RE.search(stderr):
            wall_s, user_s, sys_s = float(m.group(1)), float(m.group(2)), float(m.group(3))
        if m := BSD_RSS_RE.search(stderr):
            rss_bytes = int(m.group(1))
    elif use_gnu:
        if m := GNU_USER_RE.search(stderr):
            user_s = float(m.group(1))
        if m := GNU_SYS_RE.search(stderr):
            sys_s = float(m.group(1))
        if m := GNU_RSS_RE.search(stderr):
            rss_bytes = int(m.group(1)) * 1024
    return {
        "exit": proc.returncode,
        "realSeconds": round(wall_s, 4),
        "userSeconds": round(user_s, 4),
        "sysSeconds": round(sys_s, 4),
        "cpuSeconds": round(user_s + sys_s, 4),
        "peakRssBytes": rss_bytes,
        "peakRssMiB": round(rss_bytes / (1024 * 1024), 2) if rss_bytes else 0.0,
        "stdout": stdout.strip(),
        "stderrTail": "\n".join(stderr.strip().splitlines()[:8]),
    }


def compile_o1(gsc: Path, runtime_dir: Path, src: Path, dest: Path, cwd: Path, env: dict[str, str]) -> Path:
    if dest.exists():
        dest.unlink()
    proc = subprocess.run(
        [str(gsc), f"-:={runtime_dir}", "-o", str(dest), str(src)],
        cwd=str(cwd),
        env=env,
        capture_output=True,
        text=True,
        timeout=180,
    )
    if proc.returncode != 0 or not dest.exists():
        raise RuntimeError(f"gsc .o1 compile failed for {src}: rc={proc.returncode}\n{proc.stdout}\n{proc.stderr}")
    return dest


def compile_exe(
    gsc: Path, runtime_dir: Path, repo_root: Path, src: Path, dest: Path, cwd: Path, env: dict[str, str]
) -> Path:
    if dest.exists():
        dest.unlink()
    cc_opts = f"-I{runtime_dir}/lib -I{repo_root}/lib -I{runtime_dir}/include"
    proc = subprocess.run(
        [str(gsc), f"-:={runtime_dir}", "-cc-options", cc_opts, "-exe", "-o", str(dest), str(src)],
        cwd=str(cwd),
        env=env,
        capture_output=True,
        text=True,
        timeout=240,
    )
    if proc.returncode != 0 or not dest.exists():
        raise RuntimeError(f"gsc -exe compile failed for {src}: rc={proc.returncode}\n{proc.stdout}\n{proc.stderr}")
    return dest


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Gambit SMP modular true-multicore PBT & scaling suite.")
    parser.add_argument("--runtime", type=Path, default=Path("."), help="Built Gambit runtime root containing gsi/gsi and gsc/gsc")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3], help="Gambit source repo root")
    parser.add_argument("--topologies", default="p2,p4", help="Comma-separated processor topologies (e.g. p1,p2,p4)")
    parser.add_argument("--repeats", type=int, default=1, help="Repetitions per PBT target")
    parser.add_argument("--timeout", type=int, default=180, help="Per-invocation timeout in seconds")
    parser.add_argument("--include-scaling", action="store_true", help="Also run parallel compute/allocation scaling checks")
    parser.add_argument("--json-out", type=Path, help="Optional path to write structured JSON report")
    parser.add_argument("--summary-md", type=Path, help="Optional path to append GitHub Markdown summary table")
    args = parser.parse_args()

    runtime_dir = args.runtime.resolve()
    repo_root = args.repo.resolve()
    mc_src = repo_root / "tests/smp/multicore"
    gsi = runtime_dir / "gsi/gsi"
    gsc = runtime_dir / "gsc/gsc"
    if not gsi.is_file() or not gsc.is_file():
        raise FileNotFoundError(f"Built Gambit runtime binaries missing under {runtime_dir}")

    topologies = [t.strip() for t in args.topologies.split(",") if t.strip()]
    for t in topologies:
        if not re.fullmatch(r"p[1-9][0-9]*", t):
            raise ValueError(f"Invalid processor topology: {t}")

    env = build_env(runtime_dir)
    failures: list[str] = []
    report: dict = {
        "schema": "gambit-smp-multicore-suite.v1",
        "platform": platform.platform(),
        "machine": platform.machine(),
        "logicalCpus": os.cpu_count(),
        "topologies": topologies,
        "repeats": args.repeats,
        "results": {},
        "scaling": {},
        "passed": False,
    }

    with tempfile.TemporaryDirectory(prefix="gambit-multicore-") as tmp:
        work = Path(tmp)
        shutil.copy2(mc_src / "gc-hammer.scm", work / "gc-hammer.scm")

        # Build two helper dynamic .o1 bundles for C4 concurrent load stress
        c4_a = work / "c4_mod_a.scm"
        c4_b = work / "c4_mod_b.scm"
        c4_a.write_text("(define (c4-mod-a-fn x) (+ x 101))\n")
        c4_b.write_text("(define (c4-mod-b-fn x) (+ x 202))\n")
        c4_a_o1 = compile_o1(gsc, runtime_dir, c4_a, work / "c4_mod_a.o1", work, env)
        c4_b_o1 = compile_o1(gsc, runtime_dir, c4_b, work / "c4_mod_b.o1", work, env)
        env["C4_O1_LIST"] = f"{c4_a_o1}:{c4_b_o1}"

        # Compile all 8 .o1 PBT modules + C7 standalone executable
        compiled_o1: dict[str, tuple[Path, str, float | None]] = {}
        for name, filename, marker, rss_cap in PBT_O1_TARGETS:
            local_scm = work / filename
            shutil.copy2(mc_src / filename, local_scm)
            o1 = compile_o1(gsc, runtime_dir, local_scm, work / f"{name}.o1", work, env)
            compiled_o1[name] = (o1, marker, rss_cap)

        c7_scm = work / "c7-multi-vm-fault-isolation-smp.scm"
        shutil.copy2(mc_src / "c7-multi-vm-fault-isolation-smp.scm", c7_scm)
        c7_exe = compile_exe(gsc, runtime_dir, repo_root, c7_scm, work / "c7_multivm", work, env)

        # Execute all 9 PBT suites across requested topologies
        for name, (o1, marker, rss_cap) in compiled_o1.items():
            report["results"][name] = {}
            for topo in topologies:
                runs = []
                for _ in range(args.repeats):
                    r = run_timed([str(gsi), f"-:={runtime_dir},{topo}", str(o1)], work, env, args.timeout)
                    ok = r["exit"] == 0 and marker in r["stdout"]
                    if ok and rss_cap is not None and r["peakRssMiB"] > rss_cap:
                        ok = False
                        failures.append(f"{name}[{topo}]: peak RSS {r['peakRssMiB']} MiB > cap {rss_cap} MiB")
                    if not ok:
                        failures.append(
                            f"{name}[{topo}]: exit={r['exit']} marker={marker in r['stdout']} stdout={r['stdout'][-240:]!r}"
                        )
                    r["passed"] = ok
                    runs.append(r)
                report["results"][name][topo] = {
                    "passed": all(r["passed"] for r in runs),
                    "medianRealSeconds": round(statistics.median(r["realSeconds"] for r in runs), 4),
                    "medianCpuSeconds": round(statistics.median(r["cpuSeconds"] for r in runs), 4),
                    "maxPeakRssMiB": round(max(r["peakRssMiB"] for r in runs), 2),
                    "lastStdout": runs[-1]["stdout"],
                    "runs": runs,
                }
                row = report["results"][name][topo]
                status = "PASS" if row["passed"] else "FAIL"
                print(
                    f"[{status}] {name:24s} {topo}: wall={row['medianRealSeconds']:.2f}s "
                    f"cpu={row['medianCpuSeconds']:.2f}s rss={row['maxPeakRssMiB']:.1f}MiB | {row['lastStdout']}",
                    flush=True,
                )

        # C7 multi-VM fault isolation executable
        report["results"]["c7-multi-vm-fault-isolation"] = {}
        for topo in topologies:
            runs = []
            for _ in range(args.repeats):
                r = run_timed([str(c7_exe), f"-:{topo}"], work, env, args.timeout)
                ok = r["exit"] == 0 and "C7-MULTI-VM-FAULT-ISOLATION-PASS" in r["stdout"]
                if not ok:
                    failures.append(f"c7[{topo}]: exit={r['exit']} stdout={r['stdout'][-240:]!r}")
                r["passed"] = ok
                runs.append(r)
            report["results"]["c7-multi-vm-fault-isolation"][topo] = {
                "passed": all(r["passed"] for r in runs),
                "medianRealSeconds": round(statistics.median(r["realSeconds"] for r in runs), 4),
                "medianCpuSeconds": round(statistics.median(r["cpuSeconds"] for r in runs), 4),
                "maxPeakRssMiB": round(max(r["peakRssMiB"] for r in runs), 2),
                "lastStdout": runs[-1]["stdout"],
                "runs": runs,
            }
            row = report["results"]["c7-multi-vm-fault-isolation"][topo]
            status = "PASS" if row["passed"] else "FAIL"
            print(
                f"[{status}] {'c7-multi-vm-fault-isolation':24s} {topo}: wall={row['medianRealSeconds']:.2f}s "
                f"cpu={row['medianCpuSeconds']:.2f}s rss={row['maxPeakRssMiB']:.1f}MiB | {row['lastStdout']}",
                flush=True,
            )

        if args.include_scaling:
            for sname, code in SCALING_WORKLOADS.items():
                scm = work / f"{sname}.scm"
                scm.write_text(code.lstrip())
                o1 = compile_o1(gsc, runtime_dir, scm, work / f"{sname}.o1", work, env)
                extra = ",m65536" if "m65536" in sname else ""
                marker = "PAR_COMPUTE_PASS" if "compute" in sname else "PAR_ALLOC_GC_PASS"
                report["scaling"][sname] = {}
                for topo in topologies:
                    r = run_timed([str(gsi), f"-:={runtime_dir},{topo}{extra}", str(o1)], work, env, args.timeout)
                    ok = r["exit"] == 0 and marker in r["stdout"]
                    if not ok:
                        failures.append(f"scaling/{sname}[{topo}]: exit={r['exit']} stdout={r['stdout']!r}")
                    r["passed"] = ok
                    report["scaling"][sname][topo] = r
                    print(
                        f"[{'PASS' if ok else 'FAIL'}] scaling/{sname:20s} {topo}: wall={r['realSeconds']:.2f}s "
                        f"cpu={r['cpuSeconds']:.2f}s rss={r['peakRssMiB']:.1f}MiB | {r['stdout']}",
                        flush=True,
                    )

    report["failures"] = failures
    report["passed"] = len(failures) == 0

    if args.json_out:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(report, indent=2) + "\n")

    if args.summary_md:
        lines = [
            f"### Gambit SMP True-Multicore Suite (`{','.join(topologies)}` on `{platform.system()} {platform.machine()}`)",
            "",
            "| Target | " + " | ".join(f"`{t}` (wall / CPU / RSS)" for t in topologies) + " |",
            "| --- | " + " | ".join("---" for _ in topologies) + " |",
        ]
        for name, by_topo in report["results"].items():
            cells = []
            for t in topologies:
                row = by_topo[t]
                badge = "PASS" if row["passed"] else "FAIL"
                cells.append(
                    f"{badge} ({row['medianRealSeconds']:.2f}s / {row['medianCpuSeconds']:.2f}s / {row['maxPeakRssMiB']:.1f} MiB)"
                )
            lines.append(f"| `{name}` | " + " | ".join(cells) + " |")
        if report["scaling"]:
            lines += [
                "",
                "| Scaling Probe | " + " | ".join(f"`{t}` (wall / CPU / RSS)" for t in topologies) + " |",
                "| --- | " + " | ".join("---" for _ in topologies) + " |",
            ]
            for sname, by_topo in report["scaling"].items():
                cells = [
                    f"{'PASS' if by_topo[t]['passed'] else 'FAIL'} ({by_topo[t]['realSeconds']:.2f}s / {by_topo[t]['cpuSeconds']:.2f}s / {by_topo[t]['peakRssMiB']:.1f} MiB)"
                    for t in topologies
                ]
                lines.append(f"| `{sname}` | " + " | ".join(cells) + " |")
        lines.append("")
        args.summary_md.parent.mkdir(parents=True, exist_ok=True)
        with args.summary_md.open("a") as fh:
            fh.write("\n".join(lines) + "\n")

    if failures:
        print("MULTICORE SUITE FAILED:", file=sys.stderr)
        for item in failures:
            print("  -", item, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
