module uart_rx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 2_000_000
)(
    input clk,
    input resetn,
    input rx,
    output reg [7:0] data,
    output reg valid,
    output error
);

localparam CLKS_PER_BIT = (CLK_FREQ + BAUD_RATE/2) / BAUD_RATE;
localparam HALF_BIT = CLKS_PER_BIT / 2;

reg [1:0] state;
reg [$clog2(CLKS_PER_BIT)-1:0] clk_count;
reg [2:0] bit_index;
reg [7:0] rx_data;

always @(posedge clk) begin
    if (!resetn) begin
        state <= 0;
        valid <= 0;
        data <= 0;
    end else begin
        valid <= 0;
        case (state)
            0: begin // Idle
                if (!rx) begin
                    state <= 1;
                    clk_count <= 0;
                    bit_index <= 0;
                    rx_data <= 0;
                end
            end
            1: begin // Start bit
                if (clk_count == HALF_BIT-1) begin
                    if (!rx) begin
                        state <= 2;
                        clk_count <= 0;
                    end else begin
                        state <= 0;
                    end
                end else clk_count <= clk_count + 1;
            end
            2: begin // Data bits
                if (clk_count == CLKS_PER_BIT-1) begin
                    rx_data[bit_index] <= rx;
                    clk_count <= 0;
                    if (bit_index == 7) state <= 3;
                    else bit_index <= bit_index + 1;
                end else clk_count <= clk_count + 1;
            end
            3: begin // Stop bit
                if (clk_count == CLKS_PER_BIT-1) begin
                    valid <= 1;
                    data <= rx_data;
                    state <= 0;
                    bit_index <= 0;
                end else clk_count <= clk_count + 1;
            end
        endcase
    end
end

assign error = (state == 3) && (clk_count == CLKS_PER_BIT) && !rx;

endmodule 

module uart_tx #(
    parameter CLK_FREQ = 50_000_000,
    parameter BAUD_RATE = 2_000_000
)(
    input clk,
    input resetn,
    output reg tx,
    input [7:0] data,
    input valid,
    output ready
);

localparam CLKS_PER_BIT = (CLK_FREQ + BAUD_RATE/2)/ BAUD_RATE;
localparam IDLE = 0, START = 1, DATA = 2, STOP = 3;

reg [1:0] state;
reg [15:0] clk_count;
reg [2:0] bit_index;
reg [7:0] tx_data;

assign ready = (state == IDLE);

always @(posedge clk) begin
    if (!resetn) begin
        state <= IDLE;
        tx <= 1;
    end else begin
        case (state)
            IDLE: begin
                if (valid) begin
                    tx_data <= data;
                    state <= START;
                    clk_count <= 0;
                    bit_index <= 0;
                end
            end
            START: begin
                tx <= 0;
                if (clk_count == CLKS_PER_BIT-1) begin
                    state <= DATA;
                    clk_count <= 0;
                end else clk_count <= clk_count + 1;
            end
            DATA: begin
                tx <= tx_data[bit_index];
                if (clk_count == CLKS_PER_BIT-1) begin
                    if (bit_index == 7) begin
                        state <= STOP;
                    end else begin
                        bit_index <= bit_index + 1;
                    end
                    clk_count <= 0;
                end else clk_count <= clk_count + 1;
            end
            STOP: begin
                tx <= 1;
                if (clk_count == CLKS_PER_BIT-1) begin
                    state <= IDLE;
                end else clk_count <= clk_count + 1;
            end
        endcase
    end
end

endmodule 