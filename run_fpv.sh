#!/usr/bin/env bash
# Run the fpv-bench SVA checkers with SBY or VC Formal.
#
#   ./run_fpv.sh --tool {sby,vcf} --design <name|all> [--ref] [--samples]
#                [--model {gpt4,gpt3.5}] [--trace] [--covers]
#
# Without --ref/--samples both the reference and all samples run.
# --model restricts the samples to one model.
# --trace writes a VCD per CEX (and per cover with --covers) for GTKWave.
# --covers compiles the cover properties to check reachability / vacuity.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -eq 0 || " $* " == *" -h "* || " $* " == *" --help "* ]]; then
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    echo
    echo "designs: $(python3 -c "import json;print(' '.join(json.load(open('$here/scripts/designs.json'))))")"
    [[ $# -eq 0 ]] && exit 1 || exit 0
fi

exec python3 "$here/scripts/fpv.py" "$@"
