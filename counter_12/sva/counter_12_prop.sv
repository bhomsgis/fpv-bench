// counter_12: FPV checker bound to the DUT (see counter_12_bind.svh).
// a_spec_*: assertion justified by a sentence of design_description.txt.
// a_ref_*:  assertion that encodes reference-design behaviour only.
// Registers declared here are checker-side shadows, not DUT signals.
// Covers are compiled only with `define FPV_COVERS (run_fpv.sh --covers).
module counter_12_prop (
    input rst_n, input clk, input valid_count, input [3:0] out
);
default clocking cb @(posedge clk); endclocking
default disable iff (!rst_n);

a_spec_wrap_at_11: assert property ((valid_count && out == 4'd11) |=> out == 4'd0);

a_spec_increment: assert property ((valid_count && out < 4'd11) |=> out == $past(out) + 1);
a_spec_hold_when_idle: assert property ((!valid_count) |=> out == $past(out));

a_spec_out_in_range: assert property (out <= 4'd11);

always @(*) if (!rst_n) a_ref_rst_out_zero: assert (out == 4'd0);

a_spec_rst_clears_out: assert property (
    disable iff (1'b0) (!rst_n) |=> (out == 4'd0)
);

`ifdef FPV_COVERS
c_wrap_pre:     cover property (valid_count && out == 4'd11);
c_inc_pre:      cover property (valid_count && out < 4'd11);
c_idle:         cover property (!valid_count);
c_rst_asserted: cover property (disable iff (1'b0) !rst_n);
`endif
endmodule
