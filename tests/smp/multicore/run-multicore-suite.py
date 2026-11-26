#!/usr/bin/env python3
"""Modular true-multicore PBT & scaling runner for Gambit SMP (Linux & macOS).

Single source of truth shared between local engineering verification and
GitHub Actions (.github/actions/gambit-multicore-pbt).

Includes:
  - 13 adversarial PBT / torture targets (gambit-lin, gambit-stm, c1..c11)
  - 5 true-multicore scaling & bottleneck diagnostic workloads
  - Live process-group RSS and Darwin phys_footprint kill-switch (zero OOM risk)
  - Nix-free native build/test environment on macOS
"""
from __future__ import annotations

import argparse
import ctypes
import errno
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

# (name, filename, pass_marker, rss_cap_mib, extra_gambopt)
PBT_O1_TARGETS: list[tuple[str, str, str, float | None, str]] = [
    ("gambit-lin", "gambit-lin.scm", "GAMBIT-LIN-PASS", None, ""),
    ("gambit-stm", "gambit-stm.scm", "GAMBIT-STM-PASS", None, ""),
    ("c1-weak-will-table", "c1-weak-will-table-smp.scm", "C1-WEAK-WILL-TABLE-PASS", 128.0, ""),
    ("c2-heterogeneous-roots", "c2-heterogeneous-roots-gc-hammer.scm", "C2-HETEROGENEOUS-ROOTS-PASS", 256.0, ""),
    ("c3-ffi-callback-reentry", "c3-ffi-blocking-callback-reentry-smp.scm", "C3-FFI-CALLBACK-REENTRY-PASS", 128.0, ""),
    ("c4-dynamic-o1-symkey", "c4-dynamic-o1-binding-symkey-race.scm", "C4-DYNAMIC-O1-BINDING-SYMKEY-PASS", 256.0, ""),
    ("c5-multishot-cc", "c5-multishot-cc-cross-core-smp.scm", "C5-MULTISHOT-CC-CROSS-CORE-PASS", 256.0, ""),
    ("c6-parameterize-denv", "c6-parameterize-denv-isolation-smp.scm", "C6-PARAMETERIZE-DENV-ISOLATION-PASS", 256.0, ""),
    ("c8-io-close-reap", "c8-io-close-select-process-reap-smp.scm", "C8-IO-CLOSE-SELECT-PROCESS-REAP-PASS", 256.0, ""),
    ("c9-rest-kw-nursery", "c9-rest-keyword-nursery-contention-smp.scm", "C9-REST-KEYWORD-NURSERY-CONTENTION-PASS", 256.0, ",m65536"),
    ("c10-cas-lockfree-ws", "c10-cas-lockfree-workstealing-smp.scm", "C10-CAS-LOCKFREE-WORKSTEALING-PASS", 256.0, ""),
    ("c11-p02-binding-read", "c11-p02-binding-read-mutation-barrier-smp.scm", "C11-P02-BINDING-READ-BARRIER-PASS", 256.0, ""),
    ("t1-robustness-hardening", "t1-robustness-hardening-smp.scm", "T1-ROBUSTNESS-HARDENING-PASS", 256.0, ""),
    ("t3-blocking-ffi-park", "t3-blocking-ffi-park-smp.scm", "T3-BLOCKING-FFI-PARK-PASS", 256.0, ""),
    ("t4-workstealing-scheduler", "t4-workstealing-scheduler-smp.scm", "T4-WORKSTEALING-SCHEDULER-PASS", 256.0, ""),
    ("t5-generational-minor-gc", "t5-generational-minor-gc-smp.scm", "T5-GENERATIONAL-MINOR-GC-PASS", 256.0, ""),
]

# (marker, extra_gambopt, source_code)
SCALING_WORKLOADS: dict[str, tuple[str, str, str]] = {
    "par_compute_fib": (
        "PAR_COMPUTE_PASS",
        "",
        r"""
(declare (standard-bindings) (extended-bindings) (block))
(define (fib n)
  (declare (fixnum) (not safe))
  (if (< n 2)
      n
      (+ (fib (- n 1)) (fib (- n 2)))))
(define (run-par-compute)
  (let* ((s0 (##process-statistics))
         (t0 (f64vector-ref s0 2))
         (threads
          (let loop ((i 0) (acc '()))
            (if (= i 8)
                acc
                (loop (+ i 1)
                      (cons (thread-start! (make-thread (lambda () (fib 36)))) acc)))))
         (vals (map thread-join! threads))
         (s1 (##process-statistics))
         (work-real (- (f64vector-ref s1 2) t0))
         (gcs (inexact->exact (round (- (f64vector-ref s1 6) (f64vector-ref s0 6)))))
         (gc-real (- (f64vector-ref s1 5) (f64vector-ref s0 5))))
    (for-each (lambda (v) (if (not (= v 14930352)) (error "fib mismatch" v))) vals)
    (println "PAR_COMPUTE_PASS workers=8 fib36=14930352 work_real=" work-real " gcs=" gcs " gc_real=" gc-real)))
(run-par-compute)
""",
    ),
    "par_alloc_gc_m65536": (
        "PAR_ALLOC_GC_PASS",
        ",m65536",
        r"""
(declare (standard-bindings) (extended-bindings) (block))
(define (churn-worker id iters)
  (let loop ((i 0) (acc 0.0))
    (if (= i iters)
        acc
        (let* ((v (make-f64vector 256 (exact->inexact (+ id (modulo i 17)))))
               (p (list (vector i id v) (cons i (number->string i))))
               (s (+ (f64vector-ref v 0) (f64vector-ref v 255))))
          (loop (+ i 1) (+ acc s (if (pair? p) 1.0 0.0)))))))
(define (run-par-alloc)
  (let* ((s0 (##process-statistics))
         (t0 (f64vector-ref s0 2))
         (threads
          (let loop ((i 0) (acc '()))
            (if (= i 8)
                acc
                (loop (+ i 1)
                      (cons (thread-start! (make-thread (lambda () (churn-worker i 25000)))) acc)))))
         (vals (map thread-join! threads))
         (s1 (##process-statistics))
         (work-real (- (f64vector-ref s1 2) t0))
         (gcs (inexact->exact (round (- (f64vector-ref s1 6) (f64vector-ref s0 6)))))
         (gc-real (- (f64vector-ref s1 5) (f64vector-ref s0 5))))
    (for-each (lambda (v) (if (not (and (flonum? v) (> v 0.0))) (error "alloc mismatch" v))) vals)
    (println "PAR_ALLOC_GC_PASS workers=8 iters=25000 work_real=" work-real " gcs=" gcs " gc_real=" gc-real)))
(run-par-alloc)
""",
    ),
    "par_rest_alloc_m65536": (
        "PAR_REST_ALLOC_PASS",
        ",m65536",
        r"""
(declare (standard-bindings) (extended-bindings) (block))
(define (rsum a b . rest)
  (let loop ((xs rest) (acc (+ a b)))
    (if (pair? xs) (loop (cdr xs) (+ acc (car xs))) acc)))
(define (kwsum a #!key (k1 3) (k2 5) #!rest r)
  (+ a k1 k2 (length r)))
(define (rest-worker iters)
  (let loop ((i 0) (acc 0))
    (if (= i iters)
        acc
        (loop (+ i 1)
              (+ acc
                 (rsum 1 2 3 4 5 6 7 8)
                 (kwsum 1 k1: 2 k2: 4 9 10))))))
(define (run-par-rest)
  (let* ((s0 (##process-statistics))
         (t0 (f64vector-ref s0 2))
         (threads
          (let loop ((i 0) (acc '()))
            (if (= i 8)
                acc
                (loop (+ i 1)
                      (cons (thread-start! (make-thread (lambda () (rest-worker 120000)))) acc)))))
         (vals (map thread-join! threads))
         (s1 (##process-statistics))
         (work-real (- (f64vector-ref s1 2) t0))
         (gcs (inexact->exact (round (- (f64vector-ref s1 6) (f64vector-ref s0 6)))))
         (gc-real (- (f64vector-ref s1 5) (f64vector-ref s0 5))))
    (for-each (lambda (v) (if (not (= v (* 120000 45))) (error "rest mismatch" v))) vals)
    (println "PAR_REST_ALLOC_PASS workers=8 iters=120000 work_real=" work-real " gcs=" gcs " gc_real=" gc-real)))
(run-par-rest)
""",
    ),
    "par_gc_pause_live_heap": (
        "PAR_GC_LIVE_HEAP_PASS",
        ",m131072",
        r"""
(declare (standard-bindings) (extended-bindings) (block))
;; Build ~40 MiB live object graph of mixed pairs & vectors to challenge parallel GC mark/copy scaling!
(define (build-live-tree depth seed)
  (if (= depth 0)
      (vector seed (+ seed 1) (cons seed (+ seed 2)) (make-vector 6 seed))
      (cons (build-live-tree (- depth 1) (+ (* seed 2) 1))
            (build-live-tree (- depth 1) (+ (* seed 2) 2)))))
(define (sum-tree-sample t depth)
  (if (= depth 0)
      (vector-ref t 0)
      (+ (sum-tree-sample (car t) (- depth 1))
         (sum-tree-sample (cdr t) (- depth 1)))))
(define (run-par-gc-live)
  (let* ((ready (make-vector 8 #f))
         (go (make-vector 1 #f))
         (threads
          (let loop ((w 0) (acc '()))
            (if (= w 8)
                acc
                (loop (+ w 1)
                      (cons
                       (thread-start!
                        (make-thread
                         (lambda ()
                           (let ((my-tree (build-live-tree 14 (+ w 1))))
                             (vector-set! ready w #t)
                             (let wait ()
                               (if (not (vector-ref go 0))
                                   (begin (thread-yield!) (wait))))
                             (let m-loop ((i 0) (s 0))
                               (if (= i 150000)
                                   (+ s (sum-tree-sample my-tree 14))
                                   (let ((tmp (make-vector 64 (+ w i))))
                                     (m-loop (+ i 1) (+ s (vector-ref tmp 0))))))))))
                       acc)))))
         (_ (let wait-all ()
              (if (let chk ((i 0))
                    (cond ((= i 8) #t)
                          ((vector-ref ready i) (chk (+ i 1)))
                          (else #f)))
                  'ok
                  (begin (thread-yield!) (wait-all)))))
         (_ (##gc))
         (s0 (##process-statistics))
         (t0 (f64vector-ref s0 2)))
    (vector-set! go 0 #t)
    (let* ((vals (map thread-join! threads))
           (s1 (##process-statistics))
           (work-real (- (f64vector-ref s1 2) t0))
           (gcs (inexact->exact (round (- (f64vector-ref s1 6) (f64vector-ref s0 6)))))
           (gc-user (- (f64vector-ref s1 3) (f64vector-ref s0 3)))
           (gc-real (- (f64vector-ref s1 5) (f64vector-ref s0 5))))
      (for-each (lambda (v) (if (<= v 0) (error "mutator/tree mismatch" v))) vals)
      (println "PAR_GC_LIVE_HEAP_PASS workers=8 trees=8x16384 work_real=" work-real " gcs=" gcs " gc_real=" gc-real " gc_user=" gc-user))))
(run-par-gc-live)
""",
    ),
    "par_sync_mailbox_cas": (
        "PAR_SYNC_MAILBOX_PASS",
        "",
        r"""
(declare (standard-bindings) (extended-bindings) (block))
(define (cas-inc! box n)
  (let loop ((i 0))
    (if (< i n)
        (let retry ()
          (let ((old (vector-ref box 0)))
            (if (eq? (##vector-cas! box 0 (+ old 1) old) old)
                (loop (+ i 1))
                (retry)))))))
(define (run-par-sync)
  (let* ((s0 (##process-statistics))
         (t0 (f64vector-ref s0 2))
         (shared (vector 0))
         (n-workers 8)
         (per-worker 15000)
         ;; 8 independent producer->consumer mailbox pairs + shared CAS counter
         (threads
          (let loop ((w 0) (acc '()))
            (if (= w n-workers)
                acc
                (loop (+ w 1)
                      (cons
                       (thread-start!
                        (make-thread
                         (lambda ()
                           (cas-inc! shared per-worker)
                           (let ((child
                                  (thread-start!
                                   (make-thread
                                    (lambda ()
                                      (let c-loop ((k 0) (acc 0))
                                        (if (= k 4000)
                                            acc
                                            (c-loop (+ k 1) (+ acc (thread-receive))))))))))
                             (let p-loop ((k 0))
                               (if (< k 4000)
                                   (begin (thread-send child 1) (p-loop (+ k 1)))))
                             (let ((r (thread-join! child)))
                               (if (not (= r 4000)) (error "mailbox mismatch" r)))))))
                       acc)))))
         (_ (for-each thread-join! threads))
         (s1 (##process-statistics))
         (work-real (- (f64vector-ref s1 2) t0))
         (gcs (inexact->exact (round (- (f64vector-ref s1 6) (f64vector-ref s0 6)))))
         (gc-real (- (f64vector-ref s1 5) (f64vector-ref s0 5))))
    (if (not (= (vector-ref shared 0) (* n-workers per-worker)))
        (error "cas counter mismatch" (vector-ref shared 0)))
    (println "PAR_SYNC_MAILBOX_PASS workers=8 cas=" (vector-ref shared 0) " msgs=32000 work_real=" work-real " gcs=" gcs " gc_real=" gc-real)))
(run-par-sync)
""",
    ),
}

BSD_TIME_RE = re.compile(r"^\s*([0-9.]+)\s+real\s+([0-9.]+)\s+user\s+([0-9.]+)\s+sys\s*$", re.M)
BSD_RSS_RE = re.compile(r"^\s*(\d+)\s+maximum resident set size\s*$", re.M)
BSD_FP_RE = re.compile(r"^\s*(\d+)\s+peak memory footprint\s*$", re.M)
GNU_USER_RE = re.compile(r"User time \(seconds\):\s*([0-9.]+)")
GNU_SYS_RE = re.compile(r"System time \(seconds\):\s*([0-9.]+)")
GNU_RSS_RE = re.compile(r"Maximum resident set size \(kbytes\):\s*(\d+)")
WORK_REAL_RE = re.compile(r"\bwork_real=([0-9.eE+-]+)")
GC_REAL_RE = re.compile(r"\bgc_real=([0-9.eE+-]+)")
GCS_RE = re.compile(r"\bgcs=(\d+)")


class _DarwinTaskInfo(ctypes.Structure):
    _fields_ = [(n, ctypes.c_uint64) for n in (
        "virtual_size", "resident_size", "total_user", "total_system", "threads_user", "threads_system"
    )] + [(n, ctypes.c_int32) for n in (
        "policy", "faults", "pageins", "cow_faults", "messages_sent", "messages_received",
        "syscalls_mach", "syscalls_unix", "csw", "threadnum", "numrunning", "priority"
    )]


class _DarwinRusageV0(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(n, ctypes.c_uint64) for n in (
        "user_time", "system_time", "pkg_idle_wkups", "interrupt_wkups", "pageins",
        "wired_size", "resident_size", "phys_footprint", "proc_start_abstime", "proc_exit_abstime"
    )]


def sample_group_memory(pgid: int) -> tuple[int, int]:
    """Return live (rss_bytes, footprint_bytes) summed over process group `pgid`."""
    if sys.platform == "darwin":
        try:
            lib = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
            size = lib.proc_listpids(2, int(pgid), None, 0)  # PROC_PGRP_ONLY=2
            if size <= 0:
                return (0, 0)
            buf = (ctypes.c_int * (size // 4 + 256))()
            cnt = lib.proc_listpids(2, int(pgid), buf, ctypes.sizeof(buf))
            if cnt <= 0:
                return (0, 0)
            rusage = lib.proc_pid_rusage
            rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
            rusage.restype = ctypes.c_int
            rss_sum = 0
            fp_sum = 0
            for pid in set(buf[: cnt // 4]):
                if pid <= 0:
                    continue
                ti = _DarwinTaskInfo()
                if lib.proc_pidinfo(pid, 4, 0, ctypes.byref(ti), ctypes.sizeof(ti)) == ctypes.sizeof(ti):
                    rss_sum += int(ti.resident_size)
                ru = _DarwinRusageV0()
                if rusage(pid, 0, ctypes.byref(ru)) == 0:
                    fp_sum += int(ru.phys_footprint)
            return (rss_sum, max(rss_sum, fp_sum))
        except Exception:
            return (0, 0)
    # Linux fallback via /proc
    rss_sum = 0
    try:
        page_sz = os.sysconf("SC_PAGE_SIZE")
        for p in Path("/proc").iterdir():
            if not p.name.isdigit():
                continue
            try:
                stat = (p / "stat").read_text()
                fields = stat[stat.rindex(")") + 2 :].split()
                if int(fields[2]) != pgid:
                    continue
                rss_pages = int((p / "statm").read_text().split()[1])
                rss_sum += rss_pages * page_sz
            except OSError:
                continue
    except Exception:
        pass
    return (rss_sum, rss_sum)


def _kill_group(pgid: int) -> None:
    for sig in (signal.SIGSTOP, signal.SIGKILL):
        try:
            os.killpg(pgid, sig)
        except ProcessLookupError:
            return
        except PermissionError:
            pass


def build_env(runtime_dir: Path) -> dict[str, str]:
    env = {
        k: v
        for k, v in os.environ.items()
        if k not in ("GAMBOPT", "SDKROOT", "LIBRARY_PATH", "CPATH")
    }
    if sys.platform == "darwin":
        # Keep Nix out of native compiler/linker paths while preserving standard & Homebrew tools
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
    return env


def run_timed(
    cmd: list[str],
    cwd: Path,
    env: dict[str, str],
    timeout: int,
    *,
    max_footprint_bytes: int = 2 * 1024 * 1024 * 1024,
) -> dict:
    time_bin = "/usr/bin/time"
    use_bsd = sys.platform == "darwin" and Path(time_bin).is_file()
    use_gnu = sys.platform.startswith("linux") and Path(time_bin).is_file()
    wrapped = ([time_bin, "-l", *cmd] if use_bsd else ([time_bin, "-v", *cmd] if use_gnu else cmd))

    t0 = time.monotonic()
    deadline = t0 + timeout
    timed_out = False
    fp_exceeded = False
    live_peak_rss = 0
    live_peak_fp = 0

    with tempfile.TemporaryFile(mode="w+b") as out_f, tempfile.TemporaryFile(mode="w+b") as err_f:
        proc = subprocess.Popen(
            wrapped,
            cwd=str(cwd),
            env=env,
            stdout=out_f,
            stderr=err_f,
            start_new_session=True,
        )
        pgid = proc.pid
        try:
            while True:
                cur_rss, cur_fp = sample_group_memory(pgid)
                live_peak_rss = max(live_peak_rss, cur_rss)
                live_peak_fp = max(live_peak_fp, cur_fp)
                if max_footprint_bytes > 0 and cur_fp >= max_footprint_bytes:
                    fp_exceeded = True
                    _kill_group(pgid)
                    break
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    timed_out = True
                    _kill_group(pgid)
                    break
                try:
                    proc.wait(timeout=min(0.15, max(0.01, remaining)))
                    break
                except subprocess.TimeoutExpired:
                    continue
        finally:
            if proc.poll() is None:
                _kill_group(pgid)
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
            _kill_group(pgid)

        out_f.seek(0)
        err_f.seek(0)
        stdout = out_f.read().decode("utf-8", errors="replace")
        stderr = err_f.read().decode("utf-8", errors="replace")
        rc = proc.returncode if proc.returncode is not None else -9

    wall_s = time.monotonic() - t0
    user_s = sys_s = 0.0
    rss_bytes = live_peak_rss
    fp_bytes = live_peak_fp
    if use_bsd:
        if m := BSD_TIME_RE.search(stderr):
            wall_s, user_s, sys_s = float(m.group(1)), float(m.group(2)), float(m.group(3))
        if m := BSD_RSS_RE.search(stderr):
            rss_bytes = max(rss_bytes, int(m.group(1)))
        if m := BSD_FP_RE.search(stderr):
            fp_bytes = max(fp_bytes, int(m.group(1)))
    elif use_gnu:
        if m := GNU_USER_RE.search(stderr):
            user_s = float(m.group(1))
        if m := GNU_SYS_RE.search(stderr):
            sys_s = float(m.group(1))
        if m := GNU_RSS_RE.search(stderr):
            rss_bytes = max(rss_bytes, int(m.group(1)) * 1024)
            fp_bytes = max(fp_bytes, rss_bytes)

    if max_footprint_bytes > 0 and fp_bytes >= max_footprint_bytes:
        fp_exceeded = True
    if timed_out:
        rc = 124
    return {
        "exit": rc,
        "timeout": timed_out,
        "footprintLimitExceeded": fp_exceeded,
        "realSeconds": round(wall_s, 4),
        "userSeconds": round(user_s, 4),
        "sysSeconds": round(sys_s, 4),
        "cpuSeconds": round(user_s + sys_s, 4),
        "peakRssBytes": rss_bytes,
        "peakRssMiB": round(rss_bytes / (1024 * 1024), 2) if rss_bytes else 0.0,
        "peakFootprintBytes": fp_bytes,
        "peakFootprintMiB": round(fp_bytes / (1024 * 1024), 2) if fp_bytes else 0.0,
        "stdout": stdout.strip(),
        "stderrTail": (
            f"FOOTPRINT_LIMIT_EXCEEDED ({fp_bytes/(1024*1024):.1f} MiB)\n" if fp_exceeded else ""
        ) + (f"TIMEOUT after {timeout}s\n" if timed_out else "") + "\n".join(stderr.strip().splitlines()[:8]),
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
    parser.add_argument("--topologies", default="p1,p2,p4,p6,p8", help="Comma-separated processor topologies (e.g. p1,p2,p4,p6,p8)")
    parser.add_argument("--repeats", type=int, default=1, help="Repetitions per PBT target")
    parser.add_argument("--timeout", type=int, default=120, help="Per-invocation timeout in seconds")
    parser.add_argument("--max-footprint-mib", type=int, default=2048, help="Live process-group footprint kill-switch in MiB")
    parser.add_argument("--include-scaling", action="store_true", help="Also run parallel compute/allocation/GC/sync scaling checks")
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

    max_fp_bytes = args.max_footprint_mib * 1024 * 1024
    env = build_env(runtime_dir)
    failures: list[str] = []
    report: dict = {
        "schema": "gambit-smp-multicore-suite.v2",
        "platform": platform.platform(),
        "machine": platform.machine(),
        "logicalCpus": os.cpu_count(),
        "topologies": topologies,
        "repeats": args.repeats,
        "maxFootprintMiB": args.max_footprint_mib,
        "results": {},
        "scaling": {},
        "scalingSummary": {},
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

        # Compile all 12 .o1 PBT modules + C7 standalone executable
        compiled_o1: dict[str, tuple[Path, str, float | None, str]] = {}
        for name, filename, marker, rss_cap, extra_opt in PBT_O1_TARGETS:
            local_scm = work / filename
            shutil.copy2(mc_src / filename, local_scm)
            o1 = compile_o1(gsc, runtime_dir, local_scm, work / f"{name}.o1", work, env)
            compiled_o1[name] = (o1, marker, rss_cap, extra_opt)

        c7_scm = work / "c7-multi-vm-fault-isolation-smp.scm"
        shutil.copy2(mc_src / "c7-multi-vm-fault-isolation-smp.scm", c7_scm)
        c7_exe = compile_exe(gsc, runtime_dir, repo_root, c7_scm, work / "c7_multivm", work, env)

        # Execute all 12 .o1 PBT suites across requested topologies
        for name, (o1, marker, rss_cap, extra_opt) in compiled_o1.items():
            report["results"][name] = {}
            for topo in topologies:
                runs = []
                for _ in range(args.repeats):
                    r = run_timed(
                        [str(gsi), f"-:={runtime_dir},{topo}{extra_opt}", str(o1)],
                        work,
                        env,
                        args.timeout,
                        max_footprint_bytes=max_fp_bytes,
                    )
                    ok = r["exit"] == 0 and not r["footprintLimitExceeded"] and marker in r["stdout"]
                    if ok and rss_cap is not None and r["peakRssMiB"] > rss_cap:
                        ok = False
                        failures.append(f"{name}[{topo}]: peak RSS {r['peakRssMiB']} MiB > cap {rss_cap} MiB")
                    if not ok:
                        failures.append(
                            f"{name}[{topo}]: exit={r['exit']} fpLim={r['footprintLimitExceeded']} "
                            f"marker={marker in r['stdout']} stdout={r['stdout'][-240:]!r}"
                        )
                    r["passed"] = ok
                    runs.append(r)
                report["results"][name][topo] = {
                    "passed": all(r["passed"] for r in runs),
                    "medianRealSeconds": round(statistics.median(r["realSeconds"] for r in runs), 4),
                    "medianCpuSeconds": round(statistics.median(r["cpuSeconds"] for r in runs), 4),
                    "maxPeakRssMiB": round(max(r["peakRssMiB"] for r in runs), 2),
                    "maxPeakFootprintMiB": round(max(r["peakFootprintMiB"] for r in runs), 2),
                    "lastStdout": runs[-1]["stdout"],
                    "runs": runs,
                }
                row = report["results"][name][topo]
                status = "PASS" if row["passed"] else "FAIL"
                print(
                    f"[{status}] {name:24s} {topo}: wall={row['medianRealSeconds']:.2f}s "
                    f"cpu={row['medianCpuSeconds']:.2f}s rss={row['maxPeakRssMiB']:.1f}MiB "
                    f"fp={row['maxPeakFootprintMiB']:.1f}MiB | {row['lastStdout']}",
                    flush=True,
                )

        # C7 multi-VM fault isolation executable
        report["results"]["c7-multi-vm-fault-isolation"] = {}
        for topo in topologies:
            runs = []
            for _ in range(args.repeats):
                r = run_timed([str(c7_exe), f"-:{topo}"], work, env, args.timeout, max_footprint_bytes=max_fp_bytes)
                ok = r["exit"] == 0 and not r["footprintLimitExceeded"] and "C7-MULTI-VM-FAULT-ISOLATION-PASS" in r["stdout"]
                if not ok:
                    failures.append(f"c7[{topo}]: exit={r['exit']} stdout={r['stdout'][-240:]!r}")
                r["passed"] = ok
                runs.append(r)
            report["results"]["c7-multi-vm-fault-isolation"][topo] = {
                "passed": all(r["passed"] for r in runs),
                "medianRealSeconds": round(statistics.median(r["realSeconds"] for r in runs), 4),
                "medianCpuSeconds": round(statistics.median(r["cpuSeconds"] for r in runs), 4),
                "maxPeakRssMiB": round(max(r["peakRssMiB"] for r in runs), 2),
                "maxPeakFootprintMiB": round(max(r["peakFootprintMiB"] for r in runs), 2),
                "lastStdout": runs[-1]["stdout"],
                "runs": runs,
            }
            row = report["results"]["c7-multi-vm-fault-isolation"][topo]
            status = "PASS" if row["passed"] else "FAIL"
            print(
                f"[{status}] {'c7-multi-vm-fault-isolation':24s} {topo}: wall={row['medianRealSeconds']:.2f}s "
                f"cpu={row['medianCpuSeconds']:.2f}s rss={row['maxPeakRssMiB']:.1f}MiB "
                f"fp={row['maxPeakFootprintMiB']:.1f}MiB | {row['lastStdout']}",
                flush=True,
            )

        if args.include_scaling:
            for sname, (marker, extra_opt, code) in SCALING_WORKLOADS.items():
                scm = work / f"{sname}.scm"
                scm.write_text(code.lstrip())
                o1 = compile_o1(gsc, runtime_dir, scm, work / f"{sname}.o1", work, env)
                report["scaling"][sname] = {}
                p1_wall = None
                summary_by_topo = {}
                for topo in topologies:
                    r = run_timed(
                        [str(gsi), f"-:={runtime_dir},{topo}{extra_opt}", str(o1)],
                        work,
                        env,
                        args.timeout,
                        max_footprint_bytes=max_fp_bytes,
                    )
                    ok = r["exit"] == 0 and not r["footprintLimitExceeded"] and marker in r["stdout"]
                    if not ok:
                        failures.append(f"scaling/{sname}[{topo}]: exit={r['exit']} stdout={r['stdout']!r}")
                    r["passed"] = ok
                    work_real_m = WORK_REAL_RE.search(r["stdout"])
                    gc_real_m = GC_REAL_RE.search(r["stdout"])
                    gcs_m = GCS_RE.search(r["stdout"])
                    work_s = round(float(work_real_m.group(1)), 4) if work_real_m else r["realSeconds"]
                    r["workRealSeconds"] = work_s
                    r["gcRealSeconds"] = round(float(gc_real_m.group(1)), 4) if gc_real_m else 0.0
                    r["gcCount"] = int(gcs_m.group(1)) if gcs_m else 0
                    if topo == "p1" and work_s > 0:
                        p1_wall = work_s
                    p_num = int(topo[1:])
                    speedup = round(p1_wall / work_s, 2) if (p1_wall and work_s > 0) else None
                    eff = round(speedup / p_num, 3) if speedup is not None else None
                    gc_pct = round(100.0 * r["gcRealSeconds"] / work_s, 1) if work_s > 0 else 0.0
                    r["speedupVsP1"] = speedup
                    r["efficiency"] = eff
                    r["gcPausePct"] = gc_pct
                    report["scaling"][sname][topo] = r
                    summary_by_topo[topo] = {
                        "workReal": work_s,
                        "wall": r["realSeconds"],
                        "cpu": r["cpuSeconds"],
                        "speedup": speedup,
                        "efficiency": eff,
                        "gcCount": r["gcCount"],
                        "gcReal": r["gcRealSeconds"],
                        "gcPausePct": gc_pct,
                        "rssMiB": r["peakRssMiB"],
                        "fpMiB": r["peakFootprintMiB"],
                    }
                    sp_str = f" S={speedup:.2f}x E={eff:.2f}" if speedup is not None else ""
                    print(
                        f"[{'PASS' if ok else 'FAIL'}] scaling/{sname:22s} {topo}: work={work_s:.3f}s wall={r['realSeconds']:.2f}s "
                        f"cpu={r['cpuSeconds']:.2f}s{sp_str} gc={r['gcRealSeconds']:.2f}s({gc_pct:.1f}%) "
                        f"rss={r['peakRssMiB']:.1f}MiB fp={r['peakFootprintMiB']:.1f}MiB | {r['stdout']}",
                        flush=True,
                    )
                report["scalingSummary"][sname] = summary_by_topo

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
            cells = [
                f"{'PASS' if by_topo[t]['passed'] else 'FAIL'} ({by_topo[t]['medianRealSeconds']:.2f}s / {by_topo[t]['medianCpuSeconds']:.2f}s / {by_topo[t]['maxPeakRssMiB']:.1f} MiB)"
                for t in topologies
            ]
            lines.append(f"| `{name}` | " + " | ".join(cells) + " |")
        if report["scaling"]:
            lines += [
                "",
                "| Scaling Probe | " + " | ".join(f"`{t}` (wall / S / GC%)" for t in topologies) + " |",
                "| --- | " + " | ".join("---" for _ in topologies) + " |",
            ]
            for sname, by_topo in report["scaling"].items():
                cells = [
                    f"{'PASS' if by_topo[t]['passed'] else 'FAIL'} ({by_topo[t]['realSeconds']:.2f}s / {by_topo[t].get('speedupVsP1') or 1.0:.2f}x / {by_topo[t].get('gcPausePct', 0.0):.1f}%)"
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
