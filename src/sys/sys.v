// Sys - Tangcores system components 
// This manages slave SPI connection to the companion MCU, accepts ROM loading and other requests,
// and display the text overlay when needed.
// 
// Author: nand2mario, 1/2024

module sys #(
    parameter FREQ=21_477_000,
    parameter [14:0] COLOR_LOGO=15'b00000_10101_00000,
    parameter [15:0] CORE_ID=1      // 1: nestang, 2: snestang
)
(
    input clk,                      // SNES mclk
    input hclk,                     // hdmi clock
    input resetn,

    // OSD display interface
    output overlay,
    input [7:0] overlay_x,          // 0-255
    input [7:0] overlay_y,          // 0-223
    output [14:0] overlay_color,    // BGR5
    input [11:0] joy1,              // joystick 1: (R L X A RT LT DN UP START SELECT Y B)
    input [11:0] joy2,              // joystick 2

    // ROM loading interface
    output reg [7:0] rom_loading,   // 0-to-1 loading starts, 1-to-0 loading is finished
    output reg [7:0] rom_do,        // first 64 bytes are snes header + 32 bytes after snes header 
    output reg rom_do_valid,        // strobe for rom_do
    
    output reg [31:0] core_config,

    // UART interface
    input  uart_rx,
    output uart_tx
);

localparam integer STR_LEN = 73; // number of characters in the config string
localparam [8*STR_LEN-1:0] CONF_STR = "Tangcores;-;O12,OSD key,Right+Select,Select+Start,Select+RB;-;V,v20240101";

// Remove SPI parameters and add UART parameters
localparam CLK_FREQ = 50_000_000;
localparam BAUD_RATE = 2_000_000;

reg overlay_reg = 1;
assign overlay = overlay_reg;

// UART receiver signals
wire [7:0] rx_data;
wire rx_valid;
wire rx_error;

// UART transmitter signals
reg [7:0] tx_data;
reg tx_valid;
wire tx_ready;

// Instantiate UART modules
uart_rx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) uart_receiver (
    .clk(clk),
    .resetn(resetn),
    .rx(uart_rx),
    .data(rx_data),
    .valid(rx_valid),
    .error(rx_error)
);

uart_tx #(
    .CLK_FREQ(CLK_FREQ),
    .BAUD_RATE(BAUD_RATE)
) uart_transmitter (
    .clk(clk),
    .resetn(resetn),
    .tx(uart_tx),
    .data(tx_data),
    .valid(tx_valid),
    .ready(tx_ready)
);

// Command processing state machine
localparam STATE_IDLE = 0;     // waiting for command
localparam STATE_PARAM = 1;    // receiving parameters
localparam STATE_RESPONSE = 2; // sending response
reg [2:0] state;

// UART command buffer
reg [7:0] cmd_reg;
reg [31:0] data_reg;
reg [23:0] rom_remain;
reg [3:0] data_cnt;
reg [7:0] conf_str_idx;
reg tx_busy;

// Add new registers for textdisp interface
reg [7:0] x_wr;
reg [7:0] y_wr;
reg [7:0] char_wr;
reg we;

// Add these registers for cursor management
reg [7:0] cursor_x;
reg [7:0] cursor_y;

// UART commands:
 // 1                       get core config string (null-terminated)
 // 2 x[31:0]               set core config status
 // 3 x[7:0]                turn overlay on/off
 // 4 x[7:0] y[7:0]         move text cursor to (x, y)
 // 5 <string>              display null-terminated string from cursor
 // 6 loading_state[7:0]    set loading state (rom_loading)
 // 7 len[23:0] <data>      load len bytes of data to rom_do
always @(posedge clk) begin
    if (!resetn) begin
        state <= STATE_IDLE;
        cmd_reg <= 0;
        data_reg <= 0;
        rom_loading <= 0;
        rom_remain <= 0;
        core_config <= 0;
        data_cnt <= 0;
        x_wr <= 0;
        y_wr <= 0;
        char_wr <= 0;
        we <= 0;
        cursor_x <= 0;
        cursor_y <= 0;
        conf_str_idx <= 0;
        tx_busy <= 0;
    end else begin
        rom_do_valid <= 0;
        tx_valid <= 0;
        we <= 0;

        case (state)
            STATE_IDLE: if (rx_valid) begin
                cmd_reg <= rx_data;
                if (rx_data == 1)
                    state <= STATE_RESPONSE;
                else
                    state <= STATE_PARAM;
                data_cnt <= 0;
            end
            
            STATE_PARAM: if (rx_valid) begin
                data_reg <= {data_reg[23:0], rx_data};
                data_cnt <= data_cnt + 1;
                
                case (cmd_reg)
                    2: begin
                        if (data_cnt == 3) begin // Received 4 bytes
                            core_config <= {data_reg[23:0], rx_data};
                            state <= STATE_IDLE;
                        end
                    end
                    3: begin
                        overlay_reg <= rx_data[0];
                        state <= STATE_IDLE;    // Single byte command
                    end
                    4: case (data_cnt)
                        0: cursor_x <= rx_data;
                        default: begin
                            cursor_y <= rx_data;
                            state <= STATE_IDLE;
                        end
                    endcase
                    5: begin
                        if (rx_data == 0) begin // Null terminator
                            state <= STATE_IDLE;
                        end else begin
                            x_wr <= cursor_x;
                            y_wr <= cursor_y;
                            cursor_x <= cursor_x < 32 ? cursor_x + 1 : cursor_x;
                            char_wr <= rx_data;
                            we <= cursor_x < 32 && cursor_y < 28;
                        end
                    end
                    6: begin
                        rom_loading <= rx_data;
                        state <= STATE_IDLE;    // Single byte command
                    end
                    7: begin
                        if (data_cnt >= 3 && rom_remain == 0) begin
                            state <= STATE_IDLE;
                        end
                    end
                    default:
                        state <= STATE_IDLE;
                endcase
            end

            STATE_RESPONSE:                   
                if (cmd_reg == 1) begin         // Send config string as response
                    if (tx_ready && !tx_busy) begin
                        if (conf_str_idx <= STR_LEN) begin
                            tx_data <= (conf_str_idx < STR_LEN) ? 
                                CONF_STR[8*STR_LEN - 1 - (8*conf_str_idx) -: 8] : 
                                8'h00;
                            tx_valid <= 1;
                            conf_str_idx <= conf_str_idx + 1;
                            tx_busy <= 1;
                        end else begin
                            conf_str_idx <= 0;
                            state <= STATE_IDLE;
                        end
                    end
                end else begin
                    state <= STATE_IDLE;
                end
        endcase
        
        if (tx_valid && tx_ready) tx_busy <= 0;
        if (!tx_ready) tx_busy <= 0;
        
    end
end

// text display
`ifndef SIM
textdisp #(.COLOR_LOGO(COLOR_LOGO)) disp (
    .clk(clk), .hclk(hclk), .resetn(resetn),
    .x(overlay_x), .y(overlay_y), .color(overlay_color),
    .x_wr(x_wr), .y_wr(y_wr), .char_wr(char_wr),
    .we(we)
);
`endif

endmodule


