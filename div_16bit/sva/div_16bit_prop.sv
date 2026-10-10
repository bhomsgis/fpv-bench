// div_16bit: FPV checker bound to the DUT (see div_16bit_bind.svh).
// a_spec_*: assertion justified by a sentence of design_description.txt.
// a_ref_*:  assertion that encodes reference-design behaviour only.
// Registers declared here are checker-side shadows, not DUT signals.
// Covers are compiled only with `define FPV_COVERS (run_fpv.sh --covers).
module div_16bit_prop (
    input clk,
    input [15:0] A, input [7:0] B, input [15:0] result, input [15:0] odd
);
a_spec_remainder_lt_b: assert property (@(posedge clk) B != 8'd0 |-> odd < {8'd0, B});
a_ref_div0_result:     assert property (@(posedge clk) B == 8'd0 |-> result == 16'hFFFF);
a_ref_div0_odd:        assert property (@(posedge clk) B == 8'd0 |-> odd == A);

`ifdef FPV_COVERS
c_div_nz: cover property (@(posedge clk) B != 8'd0);
c_div0:   cover property (@(posedge clk) B == 8'd0);
`endif
endmodule
