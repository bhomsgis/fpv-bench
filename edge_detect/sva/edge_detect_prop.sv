// edge_detect: FPV checker bound to the DUT (see edge_detect_bind.svh).
// a_spec_*: assertion justified by a sentence of design_description.txt.
// a_ref_*:  assertion that encodes reference-design behaviour only.
// Registers declared here are checker-side shadows, not DUT signals.
// Covers are compiled only with `define FPV_COVERS (run_fpv.sh --covers).
module edge_detect_prop (
    input clk, input rst_n, input a, input rise, input down
);

reg a_d;
reg a_dd;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        a_d  <= 1'b0;
        a_dd <= 1'b0;
    end else begin
        a_d  <= a;
        a_dd <= a_d;
    end
end

always @(posedge clk) begin
    if (rst_n) begin
        a_spec_rise_on_01:         assert (!(a_d && !a_dd) || rise);
        a_spec_down_on_10:         assert (!(!a_d && a_dd) || down);
        a_spec_no_rise_without_01: assert (!rise || (a_d && !a_dd));
        a_spec_no_down_without_10: assert (!down || (!a_d && a_dd));
        a_spec_mutex:              assert (!(rise && down));
    end
end

always @* begin
    if (!rst_n) begin
        a_ref_rst_rise: assert (!rise);
        a_ref_rst_down: assert (!down);
    end
end

`ifdef FPV_COVERS
c_rise_01:     cover property (@(posedge clk) rst_n && a_d && !a_dd);
c_down_10:     cover property (@(posedge clk) rst_n && !a_d && a_dd);
c_rise_seen:   cover property (@(posedge clk) rst_n && rise);
c_down_seen:   cover property (@(posedge clk) rst_n && down);
c_rst_low:     cover property (@(posedge clk) !rst_n);
`endif
endmodule
