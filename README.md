# fpv-bench

SystemVerilog Assertion (SVA) checkers for the RTLLM v2.1 designs whose
LLM-generated samples pass the RTLLM testbench but fail logic equivalence
checking (LEC) against the reference. The checkers, samples, and scripts
reproduce the formal property verification (FPV) results of the paper
*Equivalence Checking Reveals, Assertions Clarify* (NeurIPS 2026 Workshop on
AI for Chip Design).

Every assertion is proven on the reference design. Assertions named
`a_spec_*` match a sentence of the RTLLM `design_description.txt` (the
spec-SVA set); assertions named `a_ref_*` are proven on the reference but are
not required by the specification. The reference-SVA set is the union of both.

## Layout

```
fpv-bench/
├── run_fpv.sh               entry point (see Usage)
├── scripts/
│   ├── fpv.py               SBY / VC Formal driver
│   ├── score.py             spec-SVA and reference-SVA fail rates
│   └── designs.json         clock, reset, and top-level options per design
└── <design>/
    ├── reference/           RTLLM reference RTL and design_description.txt
    ├── samples/gpt4/tN.v    GPT-4 samples (testbench pass, LEC fail)
    ├── samples/gpt3.5/tN.v  GPT-3.5 samples (testbench pass, LEC fail)
    └── sva/
        ├── <design>_prop.sv       checker module (assertions + covers)
        ├── <design>_prop_vcf.sv   VC Formal variant, only where the tools differ
        └── <design>_bind.svh      bind of the checker into the design
```

Designs: `accu`, `adder_pipe_64bit`, `counter_12`, `div_16bit`,
`edge_detect`, `fsm`, `multi_16bit`, `RAM`, `signal_generator`,
`traffic_light`, `width_8to16`. There are 35 samples: 27 from GPT-4 and 8
from GPT-3.5.

Covers are compiled only with `--covers` (they sit under
`` `ifdef FPV_COVERS ``). They check that the assertion antecedents are
reachable, so a proof is not vacuous.

## Requirements

- Python 3.9 or newer (standard library only).
- **VC Formal** (Synopsys), used for the results below. Set `VC_FORMAL_HOME`
  and the license variables (`SNPSLMD_LICENSE_FILE` or `LM_LICENSE_FILE`) in
  the environment. VCD traces are converted from FSDB with Verdi's `fsdb2vcd`
  (`$VC_FORMAL_HOME/verdi/bin/fsdb2vcd`, `$VERDI_HOME/bin/fsdb2vcd`, or
  `FSDB2VCD`).
- **SBY** (SymbiYosys) with Yices 2, as an alternative. All checkers except
  `div_16bit` use concurrent SVA and `bind`, which need a Yosys build with the
  Verific frontend (for example the Tabby CAD Suite). `div_16bit` uses only
  immediate assertions and runs on open-source Yosys.
- GTKWave to inspect the traces (optional).

## Usage

```
./run_fpv.sh --tool {sby,vcf} --design <name|all> [--ref] [--samples]
             [--model {gpt4,gpt3.5}] [--trace] [--covers]
```

| Option | Meaning |
|---|---|
| `--tool` | `sby` or `vcf`. |
| `--design` | One design name, or `all`. |
| `--ref` | Run the reference design. |
| `--samples` | Run the LLM samples. |
| `--model` | Run only the samples of one model (implies `--samples`). |
| `--trace` | Write a VCD for every counterexample (and every cover with `--covers`). |
| `--covers` | Compile the covers and report reachable / unreachable ones. |

Without `--ref` or `--samples`, both the reference and all samples run.
Further options: `--out DIR` (default `results/`), `--timeout SECONDS`, and
`--vcf-max-time SECONDS` (VC Formal per-property budget, default 180 s;
`div_16bit` uses 900 s).

Examples:

```bash
# Every design with SBY, reference and samples
./run_fpv.sh --tool sby --design all

# Reference only, with covers, on VC Formal
./run_fpv.sh --tool vcf --design accu --ref --covers

# GPT-3.5 samples of one design, with counterexample waveforms
./run_fpv.sh --tool sby --design edge_detect --model gpt3.5 --trace

# Fail rates over the samples
python3 scripts/score.py results/sby/results.json
```

Each target prints one line: status (`PASS`, `FAIL`, `UNKNOWN`, `ERROR`),
the failing `a_spec_*` and `a_ref_*` assertions, and, with `--covers`, the
cover counts. Results accumulate in `results/<tool>/results.json`; traces go
to `results/<tool>/traces/<design>/<target>/`, and tool logs and work files
to `results/<tool>/work/<design>/<target>/`.

### How the tools are run

Both tools assert reset in the initial state only and leave it unconstrained
afterwards, so assertions about behaviour while reset is held are checked.

- **VC Formal**: FPV app, `sim_force` on the reset pin for the initial state
  (no `set_constant`), vacuity and witness checks enabled, and a per-property
  time budget. Every property is checked independently.
- **SBY**: `smtbmc yices`, depth 25, prove mode (BMC for `fsm` and
  `div_16bit`). Reset is an `initial assume` of the reset pin in the first cycle only. SBY stops at the first
  counterexample, so a failing target is re-run in BMC mode with
  `smtbmc --keep-going` to report every failing assertion.
- The sample's module is renamed to the design name when needed (the adder
  reference module is `verified_adder_64bit`); the RTL is otherwise
  unchanged. `div_16bit` is combinational: a wrapper instantiates the design
  and the checker side by side (VC Formal also gets a dummy clock).

## Scoring

`scripts/score.py` reads `results.json` and reports, per model:

- **reference-SVA fail**: the sample fails at least one assertion;
- **spec-SVA fail**: the sample fails at least one `a_spec_*` assertion.

All reference designs must `PASS` for the numbers to be meaningful.

## Expected results

With VC Formal X-2025.06-SP2 (`./run_fpv.sh --tool vcf --design all --covers`),
every reference design proves all its assertions, none vacuous, and every
cover is reachable. Over the 35 samples:

| Model | Samples | Reference-SVA fail | Spec-SVA fail |
|---|---|---|---|
| GPT-4 | 27 | 20 (74.1%) | 6 (22.2%) |
| GPT-3.5 | 8 | 5 (62.5%) | 3 (37.5%) |

These are the counts reported in the paper. `python3 scripts/score.py` prints the same table from a `results.json`.

## License

The checkers and scripts are released under the MIT License (`LICENSE`).
The reference designs, design descriptions, and samples come from
[RTLLM](https://github.com/hkust-zhiyao/RTLLM) v2.1 and keep their MIT
License (`NOTICE`).

## Citation

If you use fpv-bench, please cite the paper *Equivalence Checking Reveals,
Assertions Clarify* (NeurIPS 2026 Workshop on AI for Chip Design).
