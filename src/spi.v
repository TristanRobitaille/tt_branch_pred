module spi #(
    parameter NUM_BITS_OF_INST_ADDR_LATCHED_IN = 16 // Number of bits of the instruction address latched in over SPI
) (
    input wire clk, rst_n,
    input wire cs, mosi, sclk,

    output reg direction_ground_truth, data_input_done,
    output reg [NUM_BITS_OF_INST_ADDR_LATCHED_IN-1:0] inst_addr
);
    /*
    -Timeline:
        1) CS goes low
        2) On the next rising edge of SCLK, the first bit of the instruction address is latched in
        3) ...Bits are latched in until CS goes high
        4) The cycle after CS goes high is when the direction bit is latched in
    */

    reg sclk_prev, data_input_done_spi_clk, data_input_done_spi_clk_prev;
    reg [1:0] state;

    wire sclk_posedge = sclk && !sclk_prev;

    always @(posedge clk) begin
        sclk_prev <= sclk;
        data_input_done_spi_clk_prev <= data_input_done_spi_clk;
        data_input_done <= (data_input_done_spi_clk && !data_input_done_spi_clk_prev);
    end

    parameter IDLE = 2'b00, LATCHING_INST = 2'b01, LATCHING_DIRECTION = 2'b10;
    always @ (posedge clk) begin
        if (!rst_n) begin
            data_input_done_spi_clk <= 1'b0;
            state <= IDLE;
            inst_addr <= 'd0;
            direction_ground_truth <= 1'b0;
        end else begin
            if (sclk_posedge) begin
                case (state)
                    IDLE: begin
                        data_input_done_spi_clk <= 1'b0;
                        if (!cs) begin
                            state <= LATCHING_INST;
                        end
                    end
                    LATCHING_INST: begin
                        inst_addr <= {inst_addr[14:0], mosi};
                        if (cs) begin
                            state <= LATCHING_DIRECTION;
                        end
                    end
                    LATCHING_DIRECTION: begin
                        direction_ground_truth <= mosi;
                        state <= IDLE;
                        data_input_done_spi_clk <= 1'b1;
                    end
                    default:
                        state <= IDLE;
                endcase
            end
        end
    end
endmodule