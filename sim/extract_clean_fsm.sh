#!/bin/bash
# extract_clean_fsm.sh: mechanically pull the blit and display FSM fragments out of a Groovy.sv into
# include files for the frame-dumping sim. Point SRC at an upstream checkout (RAW, LZ4 and auto-blit,
# with no NLC and no double buffer) to build a calibration baseline that carries none of our changes.
# Anchor-based and fail-loud (set -e plus non-empty checks), like tools/extract_fsm.sh, so the sim
# always tests the current RTL with no hand-copy drift.
set -e
# Default to this repo's own Groovy.sv. Once NLC states are present the sim sees them and the NLC blit FSM
# is extracted too, which is what the decode-to-display gate needs.
SRC="${SRC:-$(cd "$(dirname "$0")/.." && pwd)/Groovy.sv}"
OUT="${1:-/tmp/clean_fsm_gen}"
mkdir -p "$OUT"
[ -f "$SRC" ] || { echo "clean source not found: $SRC"; exit 1; }

x() { # x <name> <start-regex> <end-regex>  (start inclusive, end exclusive)
  local name="$1" a="$2" b="$3"
  awk -v a="$a" -v b="$b" '$0 ~ a {on=1} on && $0 ~ b {exit} on {print}' "$SRC" > "$OUT/$name"
  [ -s "$OUT/$name" ] || { echo "EXTRACT FAILED: $name (anchor: $a)"; exit 1; }
  echo "  $name: $(wc -l < "$OUT/$name") lines"
}

echo "extracting CLEAN FSM from $SRC into $OUT:"
# the decode_pixel task (writes vram_wren*/r_vram_in* + advances px counters)
x decode_pixel.vh  'task decode_pixel;'                 '^endtask' ; echo 'endtask' >> "$OUT/decode_pixel.vh"
# the frameskip monitor (top of the main always block, before case(state))
x fskip_monitor.vh 'verify if vram has pixels needed'   'case .state.'
# the ENTIRE case(state) body (all states: Idle/Dispatcher/Raw/Auto/Switchres/Lz4/Delta/Audio).
# Extract from the case's S_Idle through the final endcase of that case (the one closing the FSM).
awk 'f&&/^   endcase/{print "      endcase"; exit} /case \(state\)/{f=1} f{print}' "$SRC" > "$OUT/states_all.vh"
[ -s "$OUT/states_all.vh" ] || { echo "EXTRACT FAILED: states_all"; exit 1; }
echo "  states_all.vh: $(wc -l < "$OUT/states_all.vh") lines"
# state-value + DDR localparams (single lines)
grep "^parameter S_"   "$SRC" | sed 's/^parameter/localparam/' > "$OUT/states_params.vh"
grep "^parameter DDR_" "$SRC" | sed 's/^parameter/localparam/' > "$OUT/ddr_params.vh"
[ -s "$OUT/states_params.vh" ] && [ -s "$OUT/ddr_params.vh" ] || { echo "EXTRACT FAILED: params"; exit 1; }
echo "  states_params.vh: $(wc -l < "$OUT/states_params.vh") lines"
echo "  ddr_params.vh: $(wc -l < "$OUT/ddr_params.vh") lines"
echo "done."
