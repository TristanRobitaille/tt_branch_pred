/*
 * Copyright (c) 2024 Tristan Robitaille
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_branch_pred #(
    parameter NUM_BITS_OF_INST_ADDR_LATCHED_IN = 16
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
    //             RESET 
    //---------------------------------
    always @ (posedge clk) begin
        if (!rst_n) begin
        end
    end
endmodule
