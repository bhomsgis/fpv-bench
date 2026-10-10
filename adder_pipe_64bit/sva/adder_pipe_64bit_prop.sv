// adder_pipe_64bit: FPV checker bound to the DUT (see adder_pipe_64bit_bind.svh).
// a_spec_*: assertion justified by a sentence of design_description.txt.
// a_ref_*:  assertion that encodes reference-design behaviour only.
// Registers declared here are checker-side shadows, not DUT signals.
// Covers are compiled only with `define FPV_COVERS (run_fpv.sh --covers).
module adder_pipe_64bit_prop (
    input clk, input rst_n, input i_en,
    input [63:0] adda, input [63:0] addb,
    input [64:0] result, input o_en
);
default clocking cb @(posedge clk); endclocking
default disable iff (!rst_n);

a_ref_o_en_latency_4: assert property ($rose(i_en) |-> ##4 o_en);
a_ref_o_en_follows_i_en: assert property (o_en |-> $past(i_en, 4));

a_ref_result_is_sum: assert property (
    o_en |-> result == ({1'b0, $past(adda, 4)} + {1'b0, $past(addb, 4)})
);

a_spec_o_en_after_i_en: assert property ($rose(i_en) |-> ##[1:16] o_en);

a_spec_result_is_sum: assert property (
    $rose(o_en) |-> (
           result == ({1'b0, $past(adda, 1)} + {1'b0, $past(addb, 1)})
        || result == ({1'b0, $past(adda, 2)} + {1'b0, $past(addb, 2)})
        || result == ({1'b0, $past(adda, 3)} + {1'b0, $past(addb, 3)})
        || result == ({1'b0, $past(adda, 4)} + {1'b0, $past(addb, 4)})
        || result == ({1'b0, $past(adda, 5)} + {1'b0, $past(addb, 5)})
        || result == ({1'b0, $past(adda, 6)} + {1'b0, $past(addb, 6)})
        || result == ({1'b0, $past(adda, 7)} + {1'b0, $past(addb, 7)})
        || result == ({1'b0, $past(adda, 8)} + {1'b0, $past(addb, 8)})
    )
);

`ifdef FPV_COVERS
c_rose_i_en: cover property ($rose(i_en));
c_o_en:      cover property (o_en);
c_spec_rose_i_en: cover property ($rose(i_en));
`endif
endmodule
