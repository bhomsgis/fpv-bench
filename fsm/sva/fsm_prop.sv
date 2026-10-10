// fsm: FPV checker bound to the DUT (see fsm_bind.svh).
// a_spec_*: assertion justified by a sentence of design_description.txt.
// a_ref_*:  assertion that encodes reference-design behaviour only.
// Registers declared here are checker-side shadows, not DUT signals.
// Covers are compiled only with `define FPV_COVERS (run_fpv.sh --covers).
module fsm_prop (
    input IN, input MATCH, input CLK, input RST
);
reg [3:0] hist;

always @(posedge CLK or posedge RST) begin
    if (RST)
        hist <= 4'b0;
    else
        hist <= {hist[2:0], IN};
end

wire pat_10011 = ({hist, IN} == 5'b10011);

always @* begin
    if (!RST) begin
        a_spec_match_on_10011:       assert (!pat_10011 || MATCH);
        a_spec_no_match_unless_10011: assert (!MATCH || pat_10011);

        a_spec_match_implies_in:     assert (!MATCH || IN);
    end
    a_spec_reset_clears: assert (!RST || !MATCH);
end

`ifdef FPV_COVERS
c_pat_10011: cover property (@(posedge CLK) !RST && pat_10011);
c_match:     cover property (@(posedge CLK) !RST && MATCH);
c_rst_high:  cover property (@(posedge CLK) RST);
`endif
endmodule
