/*
 * Copyright (c) 2024 Tristan Robitaille
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_branch_pred #(
    parameter NUM_BITS_OF_INST_ADDR_LATCHED_IN = 16,
    parameter HISTORY_LENGTH = 16,
    parameter BIT_WIDTH_WEIGHTS = 8, // Must be 2, 4 or 8
    parameter STORAGE_B = 128, // Ensure this is a multiple of STORAGE_PER_PERCEPTRON. If larger than 2^7, will need to modify memory since max. address is 7 bits
    parameter STORAGE_PER_PERCEPTRON = (HISTORY_LENGTH * BIT_WIDTH_WEIGHTS),
    parameter NUM_PERCEPTRONS = (STORAGE_B / STORAGE_PER_PERCEPTRON),
    parameter PERCEPTRON_INDEX_WIDTH = $clog2(NUM_PERCEPTRONS) // Must be wide enough to store NUM_PERCEPTRONS
)(
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    //---------------------------------
    //              PINS 
    //---------------------------------
    //TODO: Once final, update the following lines
    // All output pins must be assigned. If not used, assign to 0.
    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;

    // SPI inputs
    assign uio_oe[0] = 1'b0; // cs
    assign uio_oe[1] = 1'b0; // mosi
    assign uio_oe[3] = 1'b0; // sclk

    assign uo_out[0] = direction_ground_truth;
    assign uo_out[1] = data_input_done;

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, clk, rst_n, 1'b0};

    //---------------------------------
    //              SPI 
    //---------------------------------
    wire direction_ground_truth, data_input_done;
    wire [NUM_BITS_OF_INST_ADDR_LATCHED_IN-1:0] inst_addr;

    spi #(
        .NUM_BITS_OF_INST_ADDR_LATCHED_IN(NUM_BITS_OF_INST_ADDR_LATCHED_IN)
    ) spi_inst (
        .clk(clk),
        .cs(uio_in[0]), .mosi(uio_in[1]), .sclk(uio_in[3]),
        .direction_ground_truth(direction_ground_truth),
        .data_input_done(data_input_done),
        .inst_addr(inst_addr)
    );

    //---------------------------------
    //           PREDICTOR 
    //---------------------------------
    reg perceptron_index[PERCEPTRON_INDEX_WIDTH-1:0];
    reg [1:0] state_pred;
    // parameter IDLE = 2'b00, COMPUTING = 2'b01;, 

    tt_um_MichaelBell_latch_mem #(
        .RAM_BYTES(STORAGE_B)
    ) latch_mem (
        .ui_in(),  // [wr_en|x|addr]
        .uo_out(), // Data output (8b)
        .uio_in(), // Data input (8b)
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always @ (*) begin
        perceptron_index = inst_addr[PERCEPTRON_INDEX_WIDTH-1 + 2 : 2]; // Implements (inst_addr >> 2) % NUM_PERCEPTRONS
    end

    // always @ (posedge clk) begin
    //     if (!rst_n) begin
        
    //     end else begin
    //         case (state)
    //             IDLE: begin
    //                 if (data_input_done) begin
    //                     state <= COMPUTING;
    //                 end
    //             end
    //             COMPUTING: begin

    //             end
    //             xxx: begin
    //             end
    //             default:
    //                 state <= IDLE;
    //         endcase
    //     end
    // end

endmodule
