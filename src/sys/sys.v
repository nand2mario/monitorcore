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
    output reg overlay,
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

    input  sspi_cs,                 // Slave SPI connection to companion MCU
    input  sspi_clk,
    input  sspi_mosi,
    output sspi_miso
);

localparam integer STR_LEN = 73; // number of characters in the config string
localparam [8*STR_LEN-1:0] CONF_STR = "Tangcores;-;O12,OSD key,Right+Select,Select+Start,Select+RB;-;V,v20240101";

 // SPI Commands (MSB-first):
 // 1                       get core config string (null-terminated)
 // 2 x[31:0]               set core config status
 // 3 x[7:0]                turn overlay on/off
 // 4 x[7:0] y[7:0]         move text cursor to (x, y)
 // 5 <string>              display null-terminated string from cursor
 // 6 loading_state[7:0]    set loading state (rom_loading)
 // 7 len[23:0] <data>      load len bytes of data to rom_do

// SPI input synchronization
reg [2:0] sspi_sync;
always @(posedge clk) sspi_sync <= {sspi_sync[1:0], sspi_cs};
wire spi_active = ~sspi_sync[2];

reg [1:0] spi_clk_sync;
always @(posedge clk) spi_clk_sync <= {spi_clk_sync[0], sspi_clk};
wire spi_clk_rising = (spi_clk_sync == 2'b01);

reg [1:0] spi_mosi_sync;
always @(posedge clk) spi_mosi_sync <= {spi_mosi_sync[0], sspi_mosi};

// SPI shift register
reg [7:0] spi_sr;
reg [2:0] bit_cnt;
reg [7:0] cmd_reg;
reg [31:0] data_reg;
reg [23:0] rom_remain;

// Command processing state machine
localparam STATE_IDLE = 0;
localparam STATE_CMD = 1;
localparam STATE_DATA = 2;
reg [2:0] state;

// Text display control
reg [2:0] data_cnt;

// Add new registers for textdisp interface
reg [7:0] x_wr;
reg [7:0] y_wr;
reg [7:0] char_wr;
reg we;

// Add these registers for cursor management
reg [7:0] cursor_x;
reg [7:0] cursor_y;

always @(posedge clk) begin
    reg [7:0] spi_sr_t;
    if (!resetn) begin
        state <= STATE_IDLE;
        bit_cnt <= 0;
        spi_sr <= 0;
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
    end else begin
        rom_do_valid <= 0;
        
        if (spi_active) begin
            if (spi_clk_rising) begin
                spi_sr_t = {spi_sr[6:0], spi_mosi_sync[1]};
                spi_sr <= spi_sr_t;
                bit_cnt <= (bit_cnt == 7) ? 3'd0 : bit_cnt + 1;
                
                if (bit_cnt == 7) begin
                    case (state)
                        STATE_IDLE: begin
                            cmd_reg <= {spi_sr[6:0], spi_mosi_sync[1]};
                            state <= STATE_CMD;
                            data_cnt <= 0;
                        end
                        STATE_CMD: begin
                            data_reg <= {data_reg[23:0], spi_sr_t};
                            // Track data bytes received per command
                            data_cnt <= data_cnt + 1;
                            
                            case (cmd_reg)
                                // Command 1 (get config) handled in MISO block
                                2: core_config <= {data_reg[23:0], spi_sr_t}; // 4 bytes
                                3: overlay <= spi_sr_t[0];          // 1 byte
                                4: begin  // Set cursor position
                                    if (data_cnt == 1) begin
                                        cursor_x <= data_reg[7:0];
                                        cursor_y <= spi_sr_t;
                                    end
                                end
                                5: begin  // Write string
                                    if (spi_sr_t != 0) begin
                                        // Write character at current cursor position
                                        x_wr <= cursor_x;
                                        y_wr <= cursor_y;
                                        char_wr <= spi_sr_t;
                                        we <= cursor_x < 32 && cursor_y < 28;
                                        
                                        // Advance cursor
                                        if (cursor_x < 32) begin
                                            cursor_x <= cursor_x + 1;
                                        end
                                    end
                                end
                                6: if (data_cnt == 0) rom_loading <= spi_sr_t;
                                7: begin  // 3 byte length + data
                                    if (data_cnt < 2) begin
                                        data_reg <= {data_reg[15:0], spi_sr_t};
                                    end else if (data_cnt == 2) begin
                                        rom_remain <= {data_reg[15:0], spi_sr_t} - 1;
                                    end else if (rom_remain != 0) begin
                                        rom_do <= spi_sr_t;
                                        rom_do_valid <= 1;
                                        rom_remain <= rom_remain - 1;
                                    end
                                end
                            endcase
                        end
                    endcase
                end
            end
        end else begin
            state <= STATE_IDLE;
            bit_cnt <= 0;
            spi_sr <= 0;
            data_cnt <= 0;  // Reset data_cnt when SPI is inactive
        end
        
        // Clear write enable after one cycle
        if (!spi_active || state != STATE_CMD) begin
            we <= 1'b0;
        end
    end
end

// SPI MISO output
reg [7:0] miso_sr;
reg [2:0] miso_bit;
reg [7:0] conf_str_idx;

always @(posedge clk) begin
    if (!spi_active) begin
        miso_sr <= 0;
        miso_bit <= 0;
        conf_str_idx <= 0;
    end else if (spi_clk_rising) begin
        if (cmd_reg == 1) begin
            // Pick the correct 8-bit chunk for the nth character from the left.
            // When conf_str_idx==0, we want the top 8 bits (character "T"),
            // then the next character when miso_bit==7.
            miso_sr <= CONF_STR[8*STR_LEN - 1 - (8*conf_str_idx) -: 8];
            conf_str_idx <= conf_str_idx + (miso_bit == 7);
        end
        miso_bit <= miso_bit + 1;
    end
end

assign sspi_miso = miso_sr[7 - miso_bit];

`ifndef IVERILOG
// text display
textdisp #(.COLOR_LOGO(COLOR_LOGO)) disp (
    .clk(clk), .hclk(hclk), .resetn(resetn),
    .x(overlay_x), .y(overlay_y), .color(overlay_color),
    .x_wr(x_wr),     // Connect new ports
    .y_wr(y_wr),
    .char_wr(char_wr),
    .we(we)
);
`else

`endif

endmodule

