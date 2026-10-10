// signal_generator: FPV checker bound to the DUT (see signal_generator_bind.svh).
// a_spec_*: assertion justified by a sentence of design_description.txt.
// a_ref_*:  assertion that encodes reference-design behaviour only.
// Registers declared here are checker-side shadows, not DUT signals.
// Covers are compiled only with `define FPV_COVERS (run_fpv.sh --covers).
module signal_generator_prop (
    input clk, input rst_n, input [4:0] wave
);
default clocking cb @(posedge clk); endclocking
default disable iff (!rst_n);

reg [1:0] st;
reg [4:0] gold_wave;
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        st        <= 2'b00;
        gold_wave <= 5'd0;
    end else begin
        case (st)
            2'b00: begin
                if (gold_wave == 5'b11111)
                    st <= 2'b01;
                else
                    gold_wave <= gold_wave + 1;
            end
            2'b01: begin
                if (gold_wave == 5'b00000)
                    st <= 2'b00;
                else
                    gold_wave <= gold_wave - 1;
            end
        endcase
    end
end

a_spec_wave_range: assert property (wave <= 5'd31);

a_spec_up_from_zero: assert property ((wave == 5'd0 && $past(wave)==5'd0) |=> (wave == 5'd1));
a_spec_down_from_peak: assert property ((wave == 5'd31 && $past(wave)==5'd31) |=> (wave == 5'd30));
a_spec_step_one: assert property (
    (wave != 5'd0 && wave != 5'd31) |=>
    (wave == $past(wave) + 1) || (wave == $past(wave) - 1)
);

a_spec_peak_hold_then_down: assert property (
    (wave == 5'd31 && $past(wave) == 5'd30) |=> (wave == 5'd31 ##1 wave == 5'd30)
);
a_spec_floor_hold_then_up: assert property (
    (wave == 5'd0 && $past(wave) == 5'd1) |=> (wave == 5'd0 ##1 wave == 5'd1)
);

a_ref_matches_golden_shadow: assert property (wave == gold_wave);

a_spec_no_mid_jump_to_zero: assert property (
    (wave >= 5'd2 && wave <= 5'd29) |=> wave != 5'd0
);

a_spec_no_triple_peak:  assert property (not (wave == 5'd31 ##1 wave == 5'd31 ##1 wave == 5'd31));
a_spec_no_triple_floor: assert property (not (wave == 5'd0  ##1 wave == 5'd0  ##1 wave == 5'd0));

a_spec_ascent_persists:  assert property ((wave == $past(wave) + 5'd1 && wave < 5'd31) |=> wave == $past(wave) + 5'd1);
a_spec_descent_persists: assert property ((wave == $past(wave) - 5'd1 && wave > 5'd0)  |=> wave == $past(wave) - 5'd1);

a_ref_state_is_two_bits: assert property ($bits(signal_generator.state) == 2);

`ifdef FPV_COVERS
c_hold_zero:   cover property (wave == 5'd0 && $past(wave) == 5'd0);
c_hold_peak:   cover property (wave == 5'd31 && $past(wave) == 5'd31);
c_interior:    cover property (wave != 5'd0 && wave != 5'd31);
c_arrive_peak: cover property (wave == 5'd31 && $past(wave) == 5'd30);
c_arrive_floor: cover property (wave == 5'd0 && $past(wave) == 5'd1);
c_rst_low:     cover property (disable iff (1'b0) !rst_n);
c_two_peak:    cover property (wave == 5'd31 ##1 wave == 5'd31);
c_two_floor:   cover property (wave == 5'd0 ##1 wave == 5'd0);
c_state_two_bits:    cover property ($bits(signal_generator.state) == 2);
`endif
endmodule
