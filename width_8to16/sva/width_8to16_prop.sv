// width_8to16: FPV checker bound to the DUT (see width_8to16_bind.svh).
// a_spec_*: assertion justified by a sentence of design_description.txt.
// a_ref_*:  assertion that encodes reference-design behaviour only.
// Registers declared here are checker-side shadows, not DUT signals.
// Covers are compiled only with `define FPV_COVERS (run_fpv.sh --covers).
module width_8to16_prop (
    input clk, input rst_n, input valid_in, input [7:0] data_in,
    input valid_out, input [15:0] data_out
);
default clocking cb @(posedge clk); endclocking
default disable iff (!rst_n);

reg       spec_have;
reg [7:0] spec_lock;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        spec_have <= 1'b0;
        spec_lock <= 8'd0;
    end else if (valid_in) begin
        spec_have <= ~spec_have;
        if (!spec_have) spec_lock <= data_in;
    end
end

a_ref_valid_out_pulse:   assert property (valid_out |=> !valid_out);
a_ref_valid_needs_input: assert property (valid_out |-> $past(valid_in));

a_spec_high_byte_first: assert property (
    (valid_in ##1 valid_in ##1 valid_out) |->
        data_out[15:8] == $past(data_in, 2) && data_out[7:0] == $past(data_in, 1)
);
a_spec_valid_only_after_pair: assert property (
    valid_out |-> $past(valid_in && spec_have));
a_spec_pair_then_valid: assert property (
    (valid_in && spec_have) |=> valid_out);
a_spec_one_input_waits: assert property (
    (valid_in && !spec_have) |=> !valid_out);
a_spec_pair_concat: assert property (
    (valid_in && spec_have) |=>
        data_out == {$past(spec_lock), $past(data_in)});

`ifdef FPV_COVERS
c_valid_out:       cover property (valid_out);
c_valid_in:        cover property (valid_in);
c_two_valids:      cover property (valid_in[->2]);
c_pair:            cover property (valid_in && spec_have);
c_one_input:       cover property (valid_in && !spec_have);
c_gap_pair:        cover property ((valid_in && !spec_have) ##1 !valid_in ##1 valid_in);
`endif
endmodule
