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

// TODO: implement slave SPI interface, and SPI command processing state machine
// Commands (all data is little-endian):
// 1: get core config string (null-terminated)
// 2 x[31:0]: set core config status (x is 32-bit)
// 3 x[7:0]: turn overlay on/off
// 4 x[7:0] y[7:0]: move text cursor to (x, y)
// 5 <string>: display null-terminated string from cursor
// 6 loading_state[7:0]: set loading state (rom_loading)
// 7 len[23:0] <data>: load len bytes of data to rom_do
// SPI command processing state machine
reg [7:0] spi_state;
reg [7:0] spi_cmd;
reg [31:0] spi_data;
reg [23:0] data_len;
reg [23:0] data_cnt;
reg [7:0] spi_byte;

localparam SPI_IDLE = 0;
localparam SPI_CMD = 1;
localparam SPI_DATA = 2;
localparam SPI_STRING = 3;

always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        spi_state <= SPI_IDLE;
        rom_loading <= 0;
        rom_do_valid <= 0;
        core_config <= 0;
        overlay <= 0;
    end else begin
        rom_do_valid <= 0; // Default to no data valid
        
        case (spi_state)
            SPI_IDLE: begin
                if (!sspi_cs) begin
                    spi_state <= SPI_CMD;
                    spi_byte <= 0;
                end
            end
            
            SPI_CMD: begin
                if (spi_byte == 0) begin
                    spi_cmd <= {spi_cmd[6:0], sspi_mosi};
                    if (spi_byte == 7) begin
                        spi_state <= SPI_DATA;
                        spi_byte <= 0;
                        spi_data <= 0;
                    end
                end
                spi_byte <= spi_byte + 1;
            end
            
            SPI_DATA: begin
                case (spi_cmd)
                    8'h01: begin // Get core config string
                        // TODO: Implement string transmission
                        spi_state <= SPI_IDLE;
                    end
                    
                    8'h02: begin // Set core config
                        spi_data <= {spi_data[30:0], sspi_mosi};
                        if (spi_byte == 31) begin
                            core_config <= spi_data;
                            spi_state <= SPI_IDLE;
                        end
                        spi_byte <= spi_byte + 1;
                    end
                    
                    8'h03: begin // Set overlay on/off
                        spi_data <= {spi_data[30:0], sspi_mosi};
                        if (spi_byte == 7) begin
                            overlay <= spi_data[0];
                            spi_state <= SPI_IDLE;
                        end
                        spi_byte <= spi_byte + 1;
                    end
                    
                    8'h04: begin // Set text cursor position
                        spi_data <= {spi_data[30:0], sspi_mosi};
                        if (spi_byte == 15) begin
                            // TODO: Set cursor position
                            spi_state <= SPI_IDLE;
                        end
                        spi_byte <= spi_byte + 1;
                    end
                    
                    8'h05: begin // Display string
                        // TODO: Implement string handling
                        spi_state <= SPI_STRING;
                    end
                    
                    8'h06: begin // Set loading state
                        spi_data <= {spi_data[30:0], sspi_mosi};
                        if (spi_byte == 7) begin
                            rom_loading <= spi_data[0];
                            spi_state <= SPI_IDLE;
                        end
                        spi_byte <= spi_byte + 1;
                    end
                    
                    8'h07: begin // Load ROM data
                        if (spi_byte < 24) begin
                            data_len <= {data_len[22:0], sspi_mosi};
                        end else begin
                            rom_do <= {rom_do[6:0], sspi_mosi};
                            rom_do_valid <= 1;
                            data_cnt <= data_cnt + 1;
                            if (data_cnt == data_len - 1) begin
                                spi_state <= SPI_IDLE;
                            end
                        end
                        spi_byte <= spi_byte + 1;
                    end
                    
                    default: spi_state <= SPI_IDLE;
                endcase
            end
            
            SPI_STRING: begin
                // TODO: Implement string handling
                if (sspi_mosi == 0) // Null terminator
                    spi_state <= SPI_IDLE;
            end
        endcase
    end
end

// text display
textdisp #(.COLOR_LOGO(COLOR_LOGO)) disp (
    .clk(clk), .hclk(hclk), .resetn(resetn),
    .x(overlay_x), .y(overlay_y), .color(overlay_color),
    .reg_char_we(textdisp_reg_char_sel ? mem_wstrb : 4'b0),
    .reg_char_di(mem_wdata) 
);


endmodule

