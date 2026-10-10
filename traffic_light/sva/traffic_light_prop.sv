// traffic_light: FPV checker bound to the DUT (see traffic_light_bind.svh).
// a_spec_*: assertion justified by a sentence of design_description.txt.
// a_ref_*:  assertion that encodes reference-design behaviour only.
// Registers declared here are checker-side shadows, not DUT signals.
// Covers are compiled only with `define FPV_COVERS (run_fpv.sh --covers).
module traffic_light_prop (
    input rst_n, input clk, input pass_request,
    input [7:0] clock, input red, input yellow, input green
);
default clocking cb @(posedge clk); endclocking
default disable iff (!rst_n);

a_spec_onehot_or_idle: assert property ((red + yellow + green) <= 1);
a_spec_red_excludes: assert property (red |-> !yellow && !green);
a_spec_yellow_excludes: assert property (yellow |-> !red && !green);
a_spec_green_excludes: assert property (green |-> !red && !yellow);

a_spec_red_to_green_order: assert property (red |=> red || green);
a_spec_green_to_yellow_order: assert property (green |=> green || yellow);
a_spec_yellow_to_red_order: assert property (yellow |=> yellow || red);
a_ref_green_holds_above_2: assert property ((green && clock > 2) |=> green);
a_ref_red_boundary: assert property ((red && clock == 3) |=> ##2 (green && clock == 60));

a_spec_pass_request_clamp: assert property (
    (green && pass_request && clock > 10) |=> clock == 10
);

a_spec_yellow_yields: assert property ($rose(yellow) |-> ##[1:5]  !yellow);
a_spec_red_yields:    assert property ($rose(red)    |-> ##[1:10] !red);

a_spec_pedestrian_clamp: assert property (
    (green && pass_request && clock > 10) |=> clock <= 10
);

`ifdef FPV_COVERS
c_red:                 cover property (red);
c_yellow:              cover property (yellow);
c_green:               cover property (green);
c_green_clock_gt2:     cover property (green && clock > 2);
c_red_clock_3:         cover property (red && clock == 3);
c_pass_req_green:      cover property (green && pass_request && clock > 10);
c_spec_rose_yellow:    cover property ($rose(yellow));
c_spec_rose_red:       cover property ($rose(red));
`endif
endmodule
