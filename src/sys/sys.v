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
    output reg rom_loading,         // 0-to-1 loading starts, 1-to-0 loading is finished
    output [7:0] rom_do,            // first 64 bytes are snes header + 32 bytes after snes header 
    output reg rom_do_valid,        // strobe for rom_do
    
    output reg [31:0] core_config,

    input  sspi_cs,                 // Slave SPI connection to companion MCU
    input  sspi_clk,
    input  sspi_mosi,
    output sspi_miso
);

localparam CONF_STR = {
    "Tangcores;",
    "-;",
    "O12,OSD key,Right+Select,Select+Start,Select+RB;",
    "-;",
    "V,v",`BUILD_DATE
};

 // SPI Commands (all data is little-endian):
 // 1                       get core config string (null-terminated)
 // 2 x[31:0]               set core config status (x is 32-bit)
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
reg textdisp_reg_char_sel;
reg [3:0] mem_wstrb;
reg [31:0] mem_wdata;

always @(posedge clk) begin
    if (!resetn) begin
        state <= STATE_IDLE;
        bit_cnt <= 0;
        spi_sr <= 0;
        cmd_reg <= 0;
        data_reg <= 0;
        rom_loading <= 0;
        rom_remain <= 0;
        core_config <= 0;
        textdisp_reg_char_sel <= 0;
        mem_wstrb <= 0;
        mem_wdata <= 0;
    end else begin
        rom_do_valid <= 0;
        
        if (spi_active) begin
            if (spi_clk_rising) begin
                spi_sr <= {spi_sr[6:0], spi_mosi_sync[1]};
                bit_cnt <= bit_cnt + 1;
                
                if (bit_cnt == 7) begin
                    case (state)
                        STATE_IDLE: begin
                            cmd_reg <= spi_sr;
                            state <= STATE_CMD;
                        end
                        STATE_CMD: begin
                            data_reg <= {data_reg[23:0], spi_sr};
                            // Track data bytes received per command
                            reg [2:0] data_cnt;
                            
                            case (cmd_reg)
                                // Command 1 (get config) handled in MISO block
                                2: if (data_cnt == 3) core_config <= {data_reg[23:0], spi_sr}; // 4 bytes
                                3: if (data_cnt == 0) textdisp_reg_char_sel <= spi_sr[0];      // 1 byte
                                4: begin  // 2 bytes (x,y)
                                    if (data_cnt == 1) begin
                                        mem_wdata <= {16'h0, data_reg[7:0], spi_sr};
                                        mem_wstrb <= 4'b1111;
                                    end
                                end
                                5: begin  // Variable length string
                                    mem_wdata <= {24'h0, spi_sr};
                                    mem_wstrb <= (spi_sr == 0) ? 4'b0000 : 4'b0001;
                                end
                                6: if (data_cnt == 0) rom_loading <= spi_sr[0];  // 1 byte
                                7: begin  // 3 byte length + data
                                    if (data_cnt < 2) begin
                                        data_reg <= {data_reg[15:0], spi_sr};
                                    end else if (data_cnt == 2) begin
                                        rom_remain <= {data_reg[15:0], spi_sr} - 1;
                                    end else if (rom_remain != 0) begin
                                        rom_do <= spi_sr;
                                        rom_do_valid <= 1;
                                        rom_remain <= rom_remain - 1;
                                    end
                                end
                            endcase
                            
                            // Increment data counter after processing byte
                            if (cmd_reg != 0) begin
                                data_cnt <= (bit_cnt == 7) ? data_cnt + 1 : data_cnt;
                                // Reset counter when starting new command
                                if (state == STATE_IDLE) data_cnt <= 0;
                            end
                        end
                    endcase
                end
            end
        end else begin
            state <= STATE_IDLE;
            bit_cnt <= 0;
            spi_sr <= 0;
            mem_wstrb <= 0;
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
            miso_sr <= CONF_STR[conf_str_idx];
            conf_str_idx <= conf_str_idx + (miso_bit == 7);
        end
        miso_bit <= miso_bit + 1;
    end
end

assign sspi_miso = miso_sr[7 - miso_bit];

// text display
textdisp #(.COLOR_LOGO(COLOR_LOGO)) disp (
    .clk(clk), .hclk(hclk), .resetn(resetn),
    .x(overlay_x), .y(overlay_y), .color(overlay_color),
    .reg_char_we(textdisp_reg_char_sel ? mem_wstrb : 4'b0),
    .reg_char_di(mem_wdata) 
);


endmodule

