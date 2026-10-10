#!/usr/bin/env python3
"""Run the fpv-bench checkers with SymbiYosys (SBY) or Synopsys VC Formal.

Called by ../run_fpv.sh. Each target (the reference design or one LLM sample)
is one job: DUT + checker + bind, proven with the same reset handling as the
paper (SBY: reset asserted in the initial state; VC Formal: create_reset).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGNS: dict = json.loads((ROOT / "scripts" / "designs.json").read_text())
MODELS = ("gpt4", "gpt3.5")
SBY_DEPTH = 25
SBY_TIMEOUT = 90
VCF_MAX_TIME = 180


# --------------------------------------------------------------------------- targets

def reference_file(design: str) -> Path:
    files = sorted((ROOT / design / "reference").glob("verified_*.v"))
    if not files:
        sys.exit(f"error: no reference RTL in {design}/reference")
    return files[0]


def targets(design: str, args) -> list[tuple[str, Path]]:
    out = []
    if args.ref:
        out.append(("reference", reference_file(design)))
    if args.samples:
        for model in ([args.model] if args.model else MODELS):
            for rtl in sorted((ROOT / design / "samples" / model).glob("t*.v")):
                out.append((f"{model}_{rtl.stem}", rtl))
    return out


def dut_text(design: str, rtl: Path) -> str:
    text = rtl.read_text(errors="replace")
    ref_mod = DESIGNS[design].get("reference_module", f"verified_{design}")
    return re.sub(rf"\bmodule\s+{re.escape(ref_mod)}\b", f"module {design}", text, count=1)


def checker_text(design: str, tool: str, covers: bool) -> str:
    sva = ROOT / design / "sva"
    chk = sva / f"{design}_prop_vcf.sv" if tool == "vcf" else None
    if chk is None or not chk.is_file():
        chk = sva / f"{design}_prop.sv"
    text = chk.read_text()
    return ("`define FPV_COVERS\n" + text) if covers else text


def short(name: str) -> str:
    return name.split(".")[-1]


# --------------------------------------------------------------------------- SBY

def sby_bin() -> str:
    return os.environ.get("SBY") or shutil.which("sby") or "sby"


def sby_assume(design: str) -> str:
    cfg = DESIGNS[design]
    if cfg.get("combinational"):
        return ""
    val = "1'b0" if cfg["reset_active"] == "low" else "1'b1"
    return (
        f"module fpv_reset_assume (input {cfg['clock']}, input {cfg['reset']});\n"
        f"    initial assume ({cfg['reset']} == {val});\n"
        f"endmodule\n"
        f"bind {design} fpv_reset_assume u_fpv_reset(.*);\n"
    )


def sby_script(design: str) -> tuple[str, list[str]]:
    cfg = DESIGNS[design]
    if cfg.get("combinational"):
        return (
            "read_verilog -sv dut.v\n"
            "read_verilog -sv prop.sv\n"
            "read_verilog -sv wrap.sv\n"
            f"prep -top {design}_wrap\n",
            ["dut.v", "prop.sv", "wrap.sv"],
        )
    return (
        "verific -sv2012 dut.v\n"
        "verific -sv2012 prop.sv\n"
        "verific -sv2012 bind.svh\n"
        "verific -sv2012 assume.sv\n"
        f"verific -import {design}\n"
        f"prep -top {design}\n",
        ["dut.v", "prop.sv", "bind.svh", "assume.sv"],
    )


def write_sources(design: str, rtl: Path, src: Path, tool: str, covers: bool) -> None:
    src.mkdir(parents=True, exist_ok=True)
    (src / "dut.v").write_text(dut_text(design, rtl))
    (src / "prop.sv").write_text(checker_text(design, tool, covers))
    (src / "bind.svh").write_text((ROOT / design / "sva" / f"{design}_bind.svh").read_text())
    cfg = DESIGNS[design]
    if cfg.get("combinational"):
        clk_port = "input vcf_clk, " if tool == "vcf" else ""
        clk_conn = "(.vcf_clk(vcf_clk), .*)" if tool == "vcf" else "(.*)"
        (src / "wrap.sv").write_text(
            f"module {design}_wrap ({clk_port}{cfg['ports']});\n"
            f"{design} dut(.*);\n"
            f"{design}_prop u_prop{clk_conn};\n"
            f"endmodule\n"
        )
    if tool == "sby":
        (src / "assume.sv").write_text(sby_assume(design))


def run_sby_task(src: Path, dest: Path, mode: str, files: list[str], script: str, timeout: int,
                 engine: str = "smtbmc yices") -> str:
    name = dest.name
    (src / f"{name}.sby").write_text(
        f"[options]\nmode {mode}\ndepth {SBY_DEPTH}\ntimeout {timeout}\n"
        f"[engines]\n{engine}\n[script]\n{script}[files]\n" + "\n".join(files) + "\n"
    )
    if dest.exists():
        shutil.rmtree(dest)
    try:
        subprocess.run([sby_bin(), "-f", "-d", str(dest), str(src / f"{name}.sby")],
                       cwd=src, capture_output=True, timeout=timeout + 60)
    except subprocess.TimeoutExpired:
        pass
    log = dest / "logfile.txt"
    return log.read_text(errors="replace") if log.is_file() else ""


def run_sby(design: str, tag: str, rtl: Path, work: Path, args) -> dict:
    src = work / "src"
    write_sources(design, rtl, src, "sby", args.covers)
    script, files = sby_script(design)
    mode = DESIGNS[design].get("sby_mode", "prove")
    log = run_sby_task(src, work / "prove", mode, files, script, args.timeout or SBY_TIMEOUT)
    status = next((s for s in ("PASS", "FAIL", "UNKNOWN", "ERROR") if f"DONE ({s}" in log), "MISSING")
    rec = {
        "status": status,
        "failed": sorted({short(n) for n in re.findall(r"failed assertion (\S+)", log)}),
        "log": str(work / "prove" / "logfile.txt"),
    }
    if "without Verific support" in log:
        rec["status"] = "ERROR"
        rec["error"] = "SBY needs a Yosys build with the Verific frontend (e.g. Tabby CAD Suite)"
    elif status in ("ERROR", "MISSING"):
        rec["error"] = next((ln.strip() for ln in log.splitlines() if "ERROR" in ln), "no SBY log")
    if status == "FAIL":
        # SBY stops at the first CEX; BMC with --keep-going reports every failing assertion.
        klog = run_sby_task(src, work / "allfails", "bmc", files, script, args.timeout or SBY_TIMEOUT,
                            engine="smtbmc --keep-going yices")
        failed, traces, vcd = set(rec["failed"]), [], None
        for ln in klog.splitlines():
            m = re.search(r"summary:\s+counterexample trace(?: \[\S+\])?: (\S+\.vcd)", ln)
            if m:
                vcd = Path(m.group(1))
            m = re.search(r"summary:\s+failed assertion (\S+)", ln)
            if not m:
                continue
            name = short(m.group(1))
            failed.add(name)
            if args.trace and vcd is not None and vcd.is_file() and name not in [Path(t).stem[4:] for t in traces]:
                traces.append(copy_trace(vcd, args, design, tag, f"cex_{name}"))
        rec["failed"] = sorted(failed)
        if args.trace:
            vcd = work / "prove" / "engine_0" / "trace.vcd"
            if not traces and vcd.is_file():
                traces = [copy_trace(vcd, args, design, tag, "cex")]
            rec["traces"] = traces
    if args.covers:
        clog = run_sby_task(src, work / "cover", "cover", files, script, args.timeout or SBY_TIMEOUT)
        reached, unreached, traces, vcd = [], [], [], None
        for ln in clog.splitlines():
            m = re.search(r"summary:\s+cover trace: (\S+\.vcd)", ln)
            if m:
                vcd = Path(m.group(1))
            m = re.search(r"summary:\s+(reached|unreached) cover statement (\S+)", ln)
            if not m:
                continue
            name = short(m.group(2))
            if m.group(1) == "unreached":
                unreached.append(name)
                continue
            reached.append(name)
            if args.trace and vcd is not None and vcd.is_file():
                traces.append(copy_trace(vcd, args, design, tag, f"cover_{name}"))
            vcd = None
        rec["covered"] = sorted(set(reached))
        rec["uncovered"] = sorted(set(unreached))
        if traces:
            rec["traces"] = rec.get("traces", []) + traces
    return rec


# --------------------------------------------------------------------------- VC Formal

def vcf_home() -> Path:
    home = os.environ.get("VC_FORMAL_HOME")
    if not home:
        sys.exit("error: set VC_FORMAL_HOME to your VC Formal (VC Static) install")
    return Path(home)


def vcf_env() -> dict:
    e = os.environ.copy()
    e["PATH"] = f"{vcf_home() / 'bin'}:{e.get('PATH', '')}"
    if e.get("TERM", "dumb") == "dumb":
        e["TERM"] = "xterm"
    ld = [p for p in e.get("LD_LIBRARY_PATH", "").split(":") if p and ".mount_" not in p]
    if ld:
        e["LD_LIBRARY_PATH"] = ":".join(ld)
    else:
        e.pop("LD_LIBRARY_PATH", None)
    return e


def vcf_tcl(design: str, src: Path, work: Path, args) -> str:
    cfg = DESIGNS[design]
    comb = cfg.get("combinational")
    top = f"{design}_wrap" if comb else design
    files = ["dut.v", "prop.sv", "wrap.sv" if comb else "bind.svh"]
    analyze = "".join(f"analyze -format sverilog {{{src / f}}}\n" for f in files)
    clock = "vcf_clk" if comb else cfg["clock"]
    reset = "" if comb else f"create_reset {cfg['reset']} -sense {cfg['reset_active']}\n"
    max_time = args.vcf_max_time or cfg.get("vcf_max_time", VCF_MAX_TIME)
    tcl = (
        f"set_fml_appmode FPV\n"
        f"set_fml_var fml_max_time {max_time}s\n"
        f"set_fml_var fml_vacuity_on true\n"
        f"set_fml_var fml_witness_on true\n"
        f"{analyze}elaborate -sva {top}\n"
        f"create_clock {clock} -period 100\n"
        f"set_change_at -default -posedge -clock {clock}\n"
        f"{reset}check_fv -block\n"
        f"report_fv -list\n"
    )
    if args.trace:
        tdir = work / "fsdb"
        usages = "{assert cover}" if args.covers else "assert"
        tcl += (
            f"file mkdir {{{tdir}}}\n"
            f"foreach_in_collection p [get_props -usage {usages} -status {{falsified covered}} -quiet] {{\n"
            f"    set n [get_attribute $p name]\n"
            f"    fvtrace -composite -property $n -file [file join {{{tdir}}} \"$n.fsdb\"]\n"
            f"}}\n"
        )
    return tcl + "exit\n"


PROP_LINE = re.compile(r"PROP_I_RESULT:\s+\S+\s+(\S+)\s+\S+\s+(\S+)\s+(\S+)", re.I)
LIST_LINE = re.compile(
    r"\[\s*\d+\]\s+(proven|falsified|inconclusive|vacuous|covered|uncoverable)"
    r"(?:\s+\([^)]+\))*\s+-\s+(\S+)", re.I)


def parse_vcf(text: str) -> dict:
    props, vac, cov = {}, {}, {}
    for m in PROP_LINE.finditer(text):
        name, kind = short(m.group(1)), m.group(3).lower()
        st = m.group(2).lower().split(":")[0]
        if st == "checking" or kind == "witness":
            continue
        if kind == "vacuity" or "vacuous" in st:
            vac[name] = "non_vacuous" if st == "non_vacuous" else "vacuous"
        elif st == "covered":
            cov[name] = "covered"
        elif st.startswith("uncover"):
            cov[name] = "uncoverable"
        elif kind == "property" and props.get(name) != "cex":
            props[name] = {"falsified": "cex", "proven": "proven"}.get(st, "inconclusive")
    for m in LIST_LINE.finditer(text):
        st, name = m.group(1).lower(), short(m.group(2))
        if st in ("covered", "uncoverable"):
            cov[name] = st
        elif st == "vacuous":
            vac[name] = "vacuous"
        elif props.get(name) != "cex":
            props[name] = {"falsified": "cex", "proven": "proven"}.get(st, "inconclusive")
    failed = sorted(n for n, s in props.items() if s == "cex")
    incon = sorted(n for n, s in props.items() if s == "inconclusive")
    if "unable to checkout" in text or "License checkout failed" in text:
        status = "LICENSE"
    elif failed:
        status = "FAIL"
    elif props and not incon:
        status = "PASS"
    elif props:
        status = "UNKNOWN"
    else:
        status = "ERROR"
    return {
        "status": status,
        "failed": failed,
        "inconclusive": incon,
        "vacuous": sorted(n for n, s in vac.items() if s == "vacuous"),
        "covered": sorted(n for n, s in cov.items() if s == "covered"),
        "uncovered": sorted(n for n, s in cov.items() if s == "uncoverable"),
    }


def fsdb2vcd() -> str | None:
    for cand in (os.environ.get("FSDB2VCD"),
                 str(vcf_home() / "verdi" / "bin" / "fsdb2vcd"),
                 os.environ.get("VERDI_HOME") and str(Path(os.environ["VERDI_HOME"]) / "bin" / "fsdb2vcd"),
                 shutil.which("fsdb2vcd")):
        if cand and Path(cand).is_file():
            return cand
    return None


def run_vcf(design: str, tag: str, rtl: Path, work: Path, args) -> dict:
    src = work / "src"
    write_sources(design, rtl, src, "vcf", args.covers)
    (work / "FPV.tcl").write_text(vcf_tcl(design, src, work, args))
    cmd = [str(vcf_home() / "bin" / "vcf"), "-full64", "-no_ui", "-session", str(work / "vcst_rtdb"),
           "-no_restore", "-f", str(work / "FPV.tcl"), "-batch"]
    logp = work / "vcf.log"
    try:
        with open(os.devnull, "rb") as devnull:
            p = subprocess.run(cmd, cwd=work, stdin=devnull, capture_output=True, text=True,
                               env=vcf_env(), timeout=(args.timeout or 3600))
        logp.write_text((p.stdout or "") + "\n" + (p.stderr or ""))
    except subprocess.TimeoutExpired as e:
        logp.write_text(f"{e.stdout or ''}\nTIMEOUT")
    text = logp.read_text(errors="replace")
    rec = parse_vcf(text)
    rec["log"] = str(logp)
    if rec["status"] in ("ERROR", "LICENSE"):
        rec["error"] = next((ln.strip() for ln in text.splitlines()
                             if "Error" in ln or "license" in ln.lower()), "no VC Formal result")
    if args.trace and (work / "fsdb").is_dir():
        conv = fsdb2vcd()
        traces = []
        for fsdb in sorted((work / "fsdb").glob("*.fsdb")):
            if fsdb.name.endswith(".xml.fsdb"):
                continue
            name = short(fsdb.stem)
            kind = "cover" if name.startswith("c_") else "cex"
            dst = trace_dir(args, design, tag) / f"{kind}_{name}"
            if conv:
                subprocess.run([conv, str(fsdb), "-o", str(dst.with_suffix(".vcd"))],
                               cwd=work / "fsdb", capture_output=True, env=vcf_env())
            if dst.with_suffix(".vcd").is_file():
                traces.append(str(dst.with_suffix(".vcd")))
            else:
                shutil.copy(fsdb, dst.with_suffix(".fsdb"))
                traces.append(str(dst.with_suffix(".fsdb")))
        rec["traces"] = traces
    return rec


# --------------------------------------------------------------------------- common

def trace_dir(args, design: str, tag: str) -> Path:
    d = Path(args.out) / args.tool / "traces" / design / tag
    d.mkdir(parents=True, exist_ok=True)
    return d


def copy_trace(vcd: Path, args, design: str, tag: str, name: str) -> str:
    dst = trace_dir(args, design, tag) / f"{name}.vcd"
    shutil.copy(vcd, dst)
    return str(dst)


def classify(failed: list[str]) -> tuple[list[str], list[str]]:
    spec = [n for n in failed if n.startswith("a_spec_")]
    return spec, [n for n in failed if n not in spec]


def main() -> int:
    ap = argparse.ArgumentParser(prog="run_fpv.sh", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tool", required=True, choices=("sby", "vcf"))
    ap.add_argument("--design", required=True, help=f"one of {', '.join(DESIGNS)} or 'all'")
    ap.add_argument("--ref", action="store_true", help="run the reference design")
    ap.add_argument("--samples", action="store_true", help="run the LLM samples")
    ap.add_argument("--model", choices=MODELS, help="only the samples of this model")
    ap.add_argument("--trace", action="store_true", help="write VCD traces of every CEX (and cover with --covers)")
    ap.add_argument("--covers", action="store_true", help="compile the covers (vacuity / reachability check)")
    ap.add_argument("--out", default=str(ROOT / "results"), help="output directory (default: results/)")
    ap.add_argument("--timeout", type=int, default=0, help="per-job wall-clock limit in seconds")
    ap.add_argument("--vcf-max-time", type=int, default=0, help=f"VC Formal fml_max_time (default {VCF_MAX_TIME}s)")
    args = ap.parse_args()

    if args.model:
        args.samples = True
    if not args.ref and not args.samples:
        args.ref = args.samples = True
    designs = list(DESIGNS) if args.design == "all" else [args.design]
    for d in designs:
        if d not in DESIGNS:
            ap.error(f"unknown design '{d}'")

    out = Path(args.out) / args.tool
    res_file = out / "results.json"
    rows = json.loads(res_file.read_text())["rows"] if res_file.is_file() else []
    runner = run_sby if args.tool == "sby" else run_vcf
    for design in designs:
        for tag, rtl in targets(design, args):
            work = out / "work" / design / tag
            if work.exists():
                shutil.rmtree(work)
            work.mkdir(parents=True)
            print(f"{args.tool} {design:17} {tag:12} ", end="", flush=True)
            t0 = time.time()
            rec = {"design": design, "target": tag, **runner(design, tag, rtl, work, args)}
            rec["elapsed_s"] = round(time.time() - t0, 1)
            spec, ref = classify(rec["failed"])
            line = f"{rec['status']:7} {rec['elapsed_s']:7.1f}s"
            if spec:
                line += f"  spec: {' '.join(spec)}"
            if ref:
                line += f"  ref: {' '.join(ref)}"
            if args.covers:
                line += f"  covers: {len(rec.get('covered', []))} hit, {len(rec.get('uncovered', []))} unreachable"
            if rec.get("vacuous"):
                line += f"  vacuous: {' '.join(rec['vacuous'])}"
            if rec.get("error"):
                line += f"  ({rec['error'][:160]})"
            print(line, flush=True)
            rows = [r for r in rows if (r["design"], r["target"]) != (design, tag)] + [rec]
            out.mkdir(parents=True, exist_ok=True)
            res_file.write_text(json.dumps({"tool": args.tool, "rows": rows}, indent=2))
    print(f"results: {res_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
