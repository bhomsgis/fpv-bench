// multi_16bit: FPV checker bound to the DUT (see multi_16bit_bind.svh).
// a_spec_*: assertion justified by a sentence of design_description.txt.
// a_ref_*:  assertion that encodes reference-design behaviour only.
// Registers declared here are checker-side shadows, not DUT signals.
// Covers are compiled only with `define FPV_COVERS (run_fpv.sh --covers).
module multi_16bit_prop (
    input clk, input rst_n, input start,
    input [15:0] ain, input [15:0] bin,
    input [31:0] yout, input done
);
default clocking cb @(posedge clk); endclocking
default disable iff (!rst_n);

a_ref_done_on_held_start: assert property (
    $rose(start) ##0 start[*18] |-> done
);

a_spec_done_after_start: assert property (
    $rose(start) ##0 start[*16] |-> ##[0:8] done
);

`ifdef FPV_COVERS
c_held_18: cover property ($rose(start) ##0 start[*18]);
c_spec_held_16: cover property ($rose(start) ##0 start[*16]);
`endif
endmodule
