/*
 * Copyright (c) 2024 Tristan Robitaille
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_branch_pred #(
    parameter NUM_BITS_OF_INST_ADDR_LATCHED_IN = 16,
    parameter HISTORY_LENGTH = 15, // Must be a power of 2 - 1 (so we can bit shift, else need to see how large a multiplier would be)
    parameter BIT_WIDTH_WEIGHTS = 8, // Must be 2, 4 or 8
    parameter STORAGE_B = 128, // If larger than 2^7, will need to modify memory since max. address is 7 bits
    parameter MEM_ADDR_WIDTH = $clog2(STORAGE_B),
    parameter STORAGE_PER_PERCEPTRON = ((HISTORY_LENGTH + 1) * BIT_WIDTH_WEIGHTS),
    parameter NUM_PERCEPTRONS = (8 * STORAGE_B / STORAGE_PER_PERCEPTRON),
    parameter PERCEPTRON_INDEX_WIDTH = $clog2(NUM_PERCEPTRONS), // Must be wide enough to store NUM_PERCEPTRONS
    parameter SUM_WIDTH = $clog2(HISTORY_LENGTH * (1 << (BIT_WIDTH_WEIGHTS-1)))
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

    /* TODO:
        -Reset weights
    */

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
    assign uo_out[2] = pred_ready;
    assign uo_out[3] = prediction;
    assign uo_out[4] = training_done;

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
        .clk(clk), .rst_n(rst_n),
        .cs(uio_in[0]), .mosi(uio_in[1]), .sclk(uio_in[3]),
        .direction_ground_truth(direction_ground_truth),
        .data_input_done(data_input_done),
        .inst_addr(inst_addr)
    );

    //---------------------------------
    //           PREDICTOR 
    //---------------------------------
    /*
        The prediction is given by
        
        The starting index (byte) of the weights for a perceptron is given by: (HISTORY_LENGTH + 1) * perceptron_index * (BIT_WIDTH_WEIGHTS/8)
    */

    reg wr_en; // 0: Read, 1: Write
    reg prediction, pred_ready, training_done;
    reg [1:0] state_pred;
    reg [7:0] mem_data_in, mem_data_out;
    reg [$clog2(HISTORY_LENGTH+1+1)-1:0] computing_cnt;
    reg [SUM_WIDTH-1:0] sum;
    reg [PERCEPTRON_INDEX_WIDTH-1:0] perceptron_index;
    reg [HISTORY_LENGTH-1:0] history_buffer;
    reg [MEM_ADDR_WIDTH-1:0] mem_addr;
    parameter IDLE = 2'd0, COMPUTING = 2'd1, TRAINING = 2'd2; 

    tt_um_MichaelBell_latch_mem #(
        .RAM_BYTES(STORAGE_B)
    ) latch_mem (
        .ui_in({wr_en, {(7-MEM_ADDR_WIDTH){1'b0}}, mem_addr}), // [wr_en|padding|addr]
        .uo_out(mem_data_out), // Data output (8b)
        .uio_in(mem_data_in),  // Data input (8b)
        .ena(ena), .clk(clk), .rst_n(rst_n),
        .uio_out(), // Unused
        .uio_oe()   // Unused
    );

    always @ (*) begin
        perceptron_index = inst_addr[PERCEPTRON_INDEX_WIDTH-1 + 2 : 2]; // Implements (inst_addr >> 2) % NUM_PERCEPTRONS
    end

    always @ (posedge clk) begin
        if (data_input_done) begin
            history_buffer <= {history_buffer[HISTORY_LENGTH-2:0], direction_ground_truth};
        end
    end

    always @ (posedge clk) begin
        if (!rst_n) begin
            mem_addr <= 'd0;
            state_pred <= IDLE;
        end else begin
            case (state_pred)
                IDLE: begin
                    wr_en <= 1'b0; // Read
                    training_done <= 1'b0;
                    computing_cnt <= 'd0;
                    if (data_input_done) begin
                        state_pred <= COMPUTING;
                        mem_addr <= (perceptron_index << $clog2(HISTORY_LENGTH + 1)); // Bit shift instead of multiply since (HISTORY_LENGTH + 1) is a power of 2
                    end
                end
                COMPUTING: begin
                    mem_addr <= mem_addr + 1;
                    computing_cnt <= computing_cnt + 1;
                    if (computing_cnt == 'd1) begin // Skip 0 because there is a delay getting SRAM data
                        sum <= mem_data_out;
                    end else if (computing_cnt < HISTORY_LENGTH+2) begin
                        if (history_buffer[computing_cnt-2]) begin
                            sum <= sum + mem_data_out;
                        end
                    end else begin
                        state_pred <= TRAINING;
                        prediction <= sum[SUM_WIDTH-1]; // Equivalent to (sum >= 0)
                        pred_ready <= 1'b1;
                    end
                end
                TRAINING: begin
                    pred_ready <= 1'b0;
                    state_pred <= IDLE;
                end
                default:
                    state_pred <= IDLE;
            endcase
        end
    end

endmodule
