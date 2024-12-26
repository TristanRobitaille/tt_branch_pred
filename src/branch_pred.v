/*
 * Copyright (c) 2024 Tristan Robitaille
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_branch_pred #(
    parameter NUM_BITS_OF_INST_ADDR_LATCHED_IN = 8,
    parameter HISTORY_LENGTH = 7, // Must be a power of 2 - 1 (so we can bit shift, else need to see how large a multiplier would be)
    parameter BIT_WIDTH_WEIGHTS = 8, // Must be 2, 4 or 8
    parameter STORAGE_B = 64, // If larger than 2^7, will need to modify memory since max. address is 7 bits
    parameter MEM_ADDR_WIDTH = $clog2(STORAGE_B),
    parameter STORAGE_PER_PERCEPTRON = ((HISTORY_LENGTH + 1) * BIT_WIDTH_WEIGHTS),
    parameter NUM_PERCEPTRONS = (8 * STORAGE_B / STORAGE_PER_PERCEPTRON),
    parameter PERCEPTRON_INDEX_WIDTH = $clog2(NUM_PERCEPTRONS), // Must be wide enough to store NUM_PERCEPTRONS
    parameter SUM_WIDTH = $clog2(HISTORY_LENGTH * (1 << (BIT_WIDTH_WEIGHTS-1))),
    parameter TRAINING_THRESHOLD = 15
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
        -Reset weights?
    */

    //---------------------------------
    //              PINS 
    //---------------------------------
    // All output pins must be assigned. If not used, assign to 0.
    assign uio_out = 8'b0;

    // SPI inputs
    assign uio_oe[0] = 1'b0; // new_data_avail
    assign uio_oe[1] = 1'b0; // direction_ground_truth
    assign uio_oe[7:2] = 'b0;
    
    assign uo_out[0] = new_data_avail_posedge;
    assign uo_out[1] = pred_ready;
    assign uo_out[2] = prediction;
    assign uo_out[3] = training_done;
    assign uo_out[7:4] = 'b0;

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, clk, rst_n, 1'b0};

    wire new_data_avail, new_data_avail_posedge;
    wire direction_ground_truth;
    wire [NUM_BITS_OF_INST_ADDR_LATCHED_IN-1:0] inst_addr;
    reg new_data_avail_prev;

    assign new_data_avail = uio_in[0];
    assign direction_ground_truth = uio_in[1];
    assign new_data_avail_posedge = (new_data_avail & ~new_data_avail_prev);
    assign inst_addr = ui_in;

    always @ (posedge clk) begin
        new_data_avail_prev <= (rst_n) ? new_data_avail : 1'b0;
    end

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
    reg [$clog2(HISTORY_LENGTH+1+1)-1:0] cnt;
    reg [SUM_WIDTH-1:0] sum;
    reg [PERCEPTRON_INDEX_WIDTH-1:0] perceptron_index;
    reg [HISTORY_LENGTH:0] history_buffer;
    reg [MEM_ADDR_WIDTH-1:0] mem_addr;
    parameter IDLE = 2'd0, COMPUTING = 2'd1, PRE_TRAINING_DELAY = 2'd2, TRAINING = 2'd3;

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
        if (!rst_n) begin
            history_buffer <= 'b0;
        end else begin
            if (training_done) begin
                history_buffer <= {history_buffer[HISTORY_LENGTH-1:0], direction_ground_truth};
            end
        end
    end

    wire [SUM_WIDTH-1:0] mem_data_out_casted = {{(SUM_WIDTH-BIT_WIDTH_WEIGHTS){mem_data_out[BIT_WIDTH_WEIGHTS-1]}}, mem_data_out};
    wire signed [SUM_WIDTH-1:0] abs_sum;
    assign abs_sum = sum[SUM_WIDTH-1] ? (~sum + 1) : sum;

    reg [1:0] substate;

    always @ (posedge clk) begin
        if (!rst_n) begin
            state_pred <= IDLE;
        end else begin
            case (state_pred)
                IDLE: begin
                    substate <= 'd0;
                    wr_en <= 1'b0; // Read
                    training_done <= 1'b0;
                    pred_ready <= 1'b0;
                    cnt <= 'd0;
                    if (new_data_avail_posedge) begin
                        state_pred <= COMPUTING;
                        mem_addr <= (perceptron_index << $clog2(HISTORY_LENGTH + 1)); // Bit shift instead of multiply since (HISTORY_LENGTH + 1) is a power of 2
                    end
                end
                COMPUTING: begin
                    cnt <= cnt + 1;
                    if (cnt == 'd0) begin
                        mem_addr <= mem_addr + 1;
                    end else if (cnt == 'd1) begin // Skip 0 because there is a delay getting SRAM data
                        sum <= mem_data_out_casted;
                        mem_addr <= mem_addr + 1;
                    end else if (cnt < HISTORY_LENGTH+2) begin
                        sum <= (history_buffer[cnt-2]) ? (sum + mem_data_out_casted) : sum; // If taken, add the weight
                        mem_addr <= mem_addr + 1;
                    end else begin
                        if ((~sum[SUM_WIDTH-1] != direction_ground_truth) | (abs_sum <= TRAINING_THRESHOLD)) begin
                            state_pred <= PRE_TRAINING_DELAY;
                            mem_addr <= (perceptron_index << $clog2(HISTORY_LENGTH + 1)); // Bit shift instead of multiply since (HISTORY_LENGTH + 1) is a power of 2
                        end else begin
                            state_pred <= IDLE;
                            training_done <= 1'b1;
                        end
                        prediction <= ~sum[SUM_WIDTH-1]; // Equivalent to (sum >= 0)
                        pred_ready <= 1'b1;
                        cnt <= 'd0;
                    end
                end
                PRE_TRAINING_DELAY: begin
                    state_pred <= TRAINING;
                    pred_ready <= 1'b0;
                end
                TRAINING: begin
                    if (substate == 0) begin // Write
                        if (cnt == 'd0) begin
                            mem_data_in <= (direction_ground_truth) ? (mem_data_out + 1) : (mem_data_out - 1);
                            substate <= 1;
                            wr_en <= 1'b1;
                        end else if (cnt < HISTORY_LENGTH+1) begin
                            mem_data_in <= (history_buffer[cnt-1] == direction_ground_truth) ? (mem_data_out + 1) : (mem_data_out - 1); // If agreement, increment the weight, else decrement
                            substate <= 1;
                            wr_en <= 1'b1;
                        end else begin
                            state_pred <= IDLE;
                            training_done <= 1'b1;
                        end
                    end else if (substate == 1) begin
                        substate <= 2;
                    end else if (substate == 2) begin // Read
                        wr_en <= 1'b0;
                        mem_addr <= mem_addr + 1;
                        cnt <= cnt + 1;
                        substate <= 3;
                    end else if (substate == 3) begin
                        substate <= 0;
                    end
                end
                default:
                    state_pred <= IDLE;
            endcase
        end
    end

endmodule
