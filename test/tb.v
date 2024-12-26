`default_nettype none
`timescale 1ns / 1ps

module tb ();
  // Dump signals
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // Input
  wire new_data_avail, direction_ground_truth, history_buffer_request;
  wire [7:0] inst_lowest_byte;

  // Output
  wire DEBUG_new_data_avail_posedge, DEBUG_state_rst_memory, DEBUG_wr_en, DEBUG_history_buffer_output;
  wire [1:0] DEBUG_state_pred;
  wire [2:0] DEBUG_perceptron_index;
  wire pred_ready, prediction, training_done, mem_reset_done;

  // Other signals
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
  
  assign uio_in[0] = new_data_avail;
  assign uio_in[1] = direction_ground_truth;
  assign uio_in[7] = history_buffer_request;
  assign ui_in = inst_lowest_byte;
  
  assign pred_ready = uo_out[0];
  assign prediction = uo_out[1];
  assign training_done = uo_out[2];
  assign mem_reset_done = uo_out[3];

  assign DEBUG_new_data_avail_posedge = uo_out[4];
  assign DEBUG_state_pred = uo_out[6:5];
  assign DEBUG_state_rst_memory = uo_out[7];

  assign DEBUG_perceptron_index = uio_out[4:2];
  assign DEBUG_wr_en = uio_out[5];
  assign DEBUG_history_buffer_output = uio_out[6];

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  tt_um_branch_pred branch_pred (
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif
      .ui_in  (ui_in),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

endmodule
