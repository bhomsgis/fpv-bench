// RAM: FPV checker bound to the DUT (see RAM_bind.svh).
// a_spec_*: assertion justified by a sentence of design_description.txt.
// a_ref_*:  assertion that encodes reference-design behaviour only.
// Registers declared here are checker-side shadows, not DUT signals.
// Covers are compiled only with `define FPV_COVERS (run_fpv.sh --covers).
module RAM_prop (
    input clk, input rst_n,
    input write_en, input [7:0] write_addr, input [5:0] write_data,
    input read_en, input [7:0] read_addr, input [5:0] read_data
);
default clocking cb @(posedge clk); endclocking
default disable iff (!rst_n);

a_spec_read_zero_when_idle: assert property ((!read_en) |=> read_data == 6'd0);

a_spec_reset_clears_read: assert property ($rose(rst_n) |-> read_data == 6'd0);

a_ref_write_then_read: assert property (
    (write_en && write_addr <= 8'd11)
    ##1 (read_en && read_addr == $past(write_addr) &&
         !(write_en && write_addr == read_addr))
    |=> read_data == $past(write_data, 2)
);

a_ref_same_cycle_read_old: assert property (
    (write_en && write_addr <= 8'd11)
    ##1 (write_en && read_en &&
         write_addr == $past(write_addr) && read_addr == write_addr)
    |=> read_data == $past(write_data, 2)
);

a_ref_hi_addr_survives_reset: assert property (
    disable iff (1'b0)
    $initstate
    ##[1:8] (rst_n && write_en && write_addr >= 8'd8 && write_addr <= 8'd11 &&
             write_data != 6'd0)
    ##1 (rst_n && !write_en)
    ##1 !rst_n
    ##1 (rst_n && read_en && read_addr == $past(write_addr, 3) &&
         !(write_en && write_addr == read_addr))
    |=> !rst_n || read_data == $past(write_data, 4)
);

a_spec_reset_clears_depth: assert property (
    disable iff (1'b0)
    $initstate
    ##[1:8] (rst_n && write_en && write_addr <= 8'd7 && write_data != 6'd0)
    ##1 (rst_n && !write_en)
    ##1 !rst_n
    ##1 (rst_n && read_en && read_addr == $past(write_addr, 3) &&
         !(write_en && write_addr == read_addr))
    |=> read_data == 6'd0
);

`ifdef FPV_COVERS
c_read_idle:       cover property (!read_en);
c_rose_rst_n:      cover property ($rose(rst_n));
c_write_in_range:  cover property (write_en && write_addr <= 8'd11);
c_write_then_read: cover property (
    (write_en && write_addr <= 8'd11)
    ##1 (read_en && read_addr == $past(write_addr) &&
         !(write_en && write_addr == read_addr))
);
c_same_cycle_rw:   cover property (
    write_en && read_en && write_addr == read_addr && write_addr <= 8'd11
);
c_hi_after_reset:  cover property (
    disable iff (1'b0)
    $initstate
    ##[1:8] (rst_n && write_en && write_addr >= 8'd8 && write_addr <= 8'd11)
    ##1 (rst_n && !write_en)
    ##1 !rst_n
    ##1 (rst_n && read_en && read_addr == $past(write_addr, 3))
);
c_spec_depth_after_reset: cover property (
    disable iff (1'b0)
    $initstate
    ##[1:8] (rst_n && write_en && write_addr <= 8'd7)
    ##1 (rst_n && !write_en)
    ##1 !rst_n
    ##1 (rst_n && read_en && read_addr == $past(write_addr, 3))
);
c_oob_write_then_read: cover property (
    (write_en && write_addr >= 8'd12)
    ##1 (read_en && read_addr == $past(write_addr) &&
         !(write_en && write_addr == read_addr))
);
`endif
endmodule
