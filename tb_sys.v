`timescale 1ns / 1ps

module tb_sys;

reg clk;
reg hclk;
reg resetn;
wire overlay;
wire [14:0] overlay_color;
wire sspi_miso;
reg sspi_cs;
reg sspi_clk;
reg sspi_mosi;

// Instantiate the DUT
sys #(
    .FREQ(21_477_000),
    .CORE_ID(1)
) dut (
    .clk(clk),
    .hclk(hclk),
    .resetn(resetn),
    .overlay(overlay),
    .overlay_x(0),
    .overlay_y(0),
    .overlay_color(overlay_color),
    .joy1(0),
    .joy2(0),
    .rom_loading(),
    .rom_do(),
    .rom_do_valid(),
    .core_config(),
    .sspi_cs(sspi_cs),
    .sspi_clk(sspi_clk),
    .sspi_mosi(sspi_mosi),
    .sspi_miso(sspi_miso)
);

// Clock generation
initial begin
    clk = 0;
    forever #23.2 clk = ~clk;  // ~21.477MHz
end

initial begin
    hclk = 0;
    forever #10 hclk = ~hclk;  // 50MHz for HDMI clock
end

// SPI task
task spi_send_task;
    input [7:0] cmd;
    input [31:0] data;
    input [23:0] extra;
    integer i;
    begin
        sspi_cs = 0;
        #100;
        
        // Send command byte
        for (i = 0; i < 8; i = i + 1) begin
            sspi_clk = 0;
            sspi_mosi = cmd[7 - i];
            #50;
            sspi_clk = 1;
            #50;
        end
        
        // Send data based on command
        case (cmd)
            2: begin // 4 bytes
                for (i = 0; i < 32; i = i + 1) begin
                    sspi_clk = 0;
                    sspi_mosi = data[31 - i];
                    #50;
                    sspi_clk = 1;
                    #50;
                end
            end
            4: begin // 2 bytes
                for (i = 0; i < 16; i = i + 1) begin
                    sspi_clk = 0;
                    sspi_mosi = data[15 - i];
                    #50;
                    sspi_clk = 1;
                    #50;
                end
            end
            7: begin // 3 byte length + data
                for (i = 0; i < 24; i = i + 1) begin
                    sspi_clk = 0;
                    sspi_mosi = extra[23 - i];
                    #50;
                    sspi_clk = 1;
                    #50;
                end
                for (i = 0; i < 8*extra; i = i + 1) begin
                    sspi_clk = 0;
                    sspi_mosi = $random;
                    #50;
                    sspi_clk = 1;
                    #50;
                end
            end
            default: begin // 1 byte
                for (i = 0; i < 8; i = i + 1) begin
                    sspi_clk = 0;
                    sspi_mosi = data[7 - i];
                    #50;
                    sspi_clk = 1;
                    #50;
                end
            end
        endcase
        
        sspi_cs = 1;
        #200;
    end
endtask

// SPI receive task
task spi_recv_task;
    output [7:0] data;
    integer i;
    begin
        sspi_cs = 0;
        #100;
        
        for (i = 0; i < 8; i = i + 1) begin
            sspi_clk = 0;
            #50;
            data[7 - i] = sspi_miso;
            sspi_clk = 1;
            #50;
        end
        
        sspi_cs = 1;
        #200;
    end
endtask

// Test procedure
initial begin
    // Initialize inputs
    resetn = 0;
    sspi_cs = 1;
    sspi_clk = 0;
    sspi_mosi = 0;
    
    // Reset sequence
    #100;
    resetn = 1;
    #100;
    
    // Test 1: Get core config string (CMD 1)
    begin : test1
        reg [7:0] recv_data;
        integer i;
        $display("Testing CMD 1 (Get core config)...");
        
        // Send command 1
        spi_send_task(1, 0, 0);
        
        // Receive response
        for (i = 0; i < 64; i = i + 1) begin
            spi_recv_task(recv_data);
            $display("Received byte %h", recv_data);
            if (recv_data === 0) break;
        end
        
        $display("CMD 1 test %s", (i < 64) ? "PASSED" : "FAILED");
    end
    
    // Test 2: Set core config (CMD 2)
    begin
        $display("Testing CMD 2 (Set core config)...");
        spi_send_task(2, 32'hA5A5A5A5, 0);
        #100;
        if (dut.core_config === 32'hA5A5A5A5)
            $display("CMD 2 test PASSED");
        else
            $display("CMD 2 test FAILED");
    end
    
    // Add more test cases for other commands...
    
    #1000;
    $finish;
end

// Monitor ROM loading signals
always @(posedge dut.rom_do_valid) begin
    $display("ROM data received: %h", dut.rom_do);
end

initial begin
    $dumpfile("tb_sys.vcd");
    $dumpvars(0, tb_sys);
end

endmodule
