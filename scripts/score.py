#!/usr/bin/env python3
"""Reference-SVA and spec-SVA fail rates over the false-positive samples.

    python3 scripts/score.py results/vcf/results.json

A sample counts as a reference-SVA fail if any assertion fails, and as a
spec-SVA fail if any a_spec_* assertion fails. Every reference design must
PASS for the numbers to be meaningful.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = {"gpt4": "GPT-4", "gpt3.5": "GPT-3.5"}


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "results" / "vcf" / "results.json"
    rows = json.loads(path.read_text())["rows"]
    refs = [r for r in rows if r["target"] == "reference"]
    bad = [r["design"] for r in refs if r["status"] != "PASS"]
    print(f"reference designs PASS: {len(refs) - len(bad)}/{len(refs)}" + (f"  (not PASS: {', '.join(bad)})" if bad else ""))
    for model, label in MODELS.items():
        samples = [r for r in rows if r["target"].startswith(model + "_")]
        n = len(samples)
        if not n:
            continue
        ref = sum(1 for r in samples if r["failed"])
        spec = sum(1 for r in samples if any(f.startswith("a_spec_") for f in r["failed"]))
        unknown = [f"{r['design']}/{r['target']}" for r in samples if r["status"] not in ("PASS", "FAIL")]
        print(f"{label:8} samples {n:3}  reference-SVA fail {ref}/{n} ({100 * ref / n:.1f}%)  "
              f"spec-SVA fail {spec}/{n} ({100 * spec / n:.1f}%)")
        if unknown:
            print(f"         not conclusive: {', '.join(unknown)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
