// accu: FPV checker bound to the DUT (see accu_bind.svh).
// a_spec_*: assertion justified by a sentence of design_description.txt.
// a_ref_*:  assertion that encodes reference-design behaviour only.
// Registers declared here are checker-side shadows, not DUT signals.
// Covers are compiled only with `define FPV_COVERS (run_fpv.sh --covers).
module accu_prop (
    input clk, input rst_n, input [7:0] data_in, input valid_in,
    input valid_out, input [9:0] data_out
);
default clocking cb @(posedge clk); endclocking
default disable iff (!rst_n);

reg [1:0] spec_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        spec_cnt <= 2'd0;
    else if (valid_in)
        spec_cnt <= spec_cnt + 2'd1;
end

a_ref_valid_out_pulse: assert property (valid_out |=> !valid_out);

a_ref_vo_within_four: assert property (!valid_out |-> ##[1:4] valid_out);

a_ref_sum_four_consecutive: assert property (
    valid_out |-> data_out == ({2'b0, $past(data_in, 4)} + {2'b0, $past(data_in, 3)}
                             + {2'b0, $past(data_in, 2)} + {2'b0, $past(data_in, 1)})
);

a_ref_pulse_adds_last_beat: assert property (
    valid_out |-> data_out == $past(data_out) + {2'b0, $past(data_in)}
);

a_ref_overlap_restarts_data: assert property (
    valid_out && valid_in |=> data_out == {2'b0, $past(data_in)}
);

a_spec_vo_after_four_valids: assert property (
    (valid_in && spec_cnt == 2'd3) |-> ##[0:4] valid_out
);

`ifdef FPV_COVERS
c_valid_out:          cover property (valid_out);
c_not_valid_out:      cover property (!valid_out);
c_overlap_valid_in:   cover property (valid_out && valid_in);
c_spec_four_valids:   cover property (valid_in && spec_cnt == 2'd3);
`endif
endmodule
