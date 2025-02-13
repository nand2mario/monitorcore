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
wire rom_loading;
wire [7:0] rom_do;
wire rom_do_valid;
wire [31:0] core_config;

// Instantiate the DUT
sys #(
    .FREQ(21_477_000),
    .CORE_ID(1)
) dut (
    .clk(clk),
    .hclk(hclk),
    .resetn(resetn),
    .overlay(overlay),
    .overlay_x(8'd0),
    .overlay_y(8'd0),
    .overlay_color(overlay_color),
    .joy1(12'd0),
    .joy2(12'd0),
    .rom_loading(rom_loading),
    .rom_do(rom_do),
    .rom_do_valid(rom_do_valid),
    .core_config(core_config),
    .sspi_cs(sspi_cs),
    .sspi_clk(sspi_clk),
    .sspi_mosi(sspi_mosi),
    .sspi_miso(sspi_miso)
);

// Clock generation
initial begin
    clk = 0;
    forever #10 clk = ~clk;     // 50Mhz
end

// SPI task
task spi_send_task;
    input [7:0] cmd;
    input [31:0] data;
    input [23:0] extra;
    input deassert;
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
            1: begin end // no data for CMD 1
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
        
        if (deassert) begin
            sspi_cs = 1;
            #200;
        end
    end
endtask

// SPI receive task
task spi_recv_task;
    output [7:0] data;
    input deassert;
    integer i;
    begin
        if (deassert) begin
            sspi_cs = 0;
            #100;
        end else begin
            // CS is expected to remain active from a prior operation.
            #100;
        end
        
        for (i = 0; i < 8; i = i + 1) begin
            sspi_clk = 0;
            #50;
            data[7 - i] = sspi_miso;
            sspi_clk = 1;
            #50;
        end
        
        if (deassert) begin
            sspi_cs = 1;
            #200;
        end
    end
endtask

// Test procedure
initial begin
    // Initialize inputs
    resetn = 0;
    sspi_cs = 1;
    sspi_clk = 0;
    sspi_mosi = 0;
    hclk = 0;
    
    // Reset sequence
    #100;
    resetn = 1;
    #100;
    
    // Test 1: Get core config string (CMD 1)
    begin : test1
        reg [7:0] recv_data;
        integer i;
        reg timeout;
        $display("Testing CMD 1 (Get core config)...");
        
        timeout = 1;
        // For CMD 1, keep CS low (pass 0) since we want a continuous transaction for receiving data.
        spi_send_task(1, 0, 0, 0);
        
        // Receive response with timeout check (keeping CS active for a continuous transaction)
        for (i = 0; i < 64; i = i + 1) begin : receive_loop
            spi_recv_task(recv_data, 0);
            $display("Received byte %h", recv_data);
            if (recv_data !== 0) begin
                timeout = 0;
                if (recv_data === 0) disable receive_loop;
            end
        end
        // Manually deassert CS at the end of the continuous CMD 1 transaction.
        sspi_cs = 1;
        #200;
        
        $display("CMD 1 test %s", timeout ? "FAILED (timeout)" : "PASSED");
    end
    
    // Test 2: Set core config (CMD 2)
    begin
        $display("Testing CMD 2 (Set core config)...");
        // For CMD 2, deassert CS after sending so the transaction completes.
        spi_send_task(2, 32'hA5A5A5A5, 0, 1);
        #1000;
        if (core_config === 32'hA5A5A5A5)
            $display("CMD 2 test PASSED");
        else
            $display("CMD 2 test FAILED (core_config = %h)", core_config);
    end
    
    // Add more test cases for other commands...
    
    #1000;
    $finish;
end

// Monitor ROM loading signals
always @(posedge dut.rom_do_valid) begin
    $display("ROM data received: %h", dut.rom_do);
end

// Add hclk generation
initial begin
    hclk = 0;
    forever #5 hclk = ~hclk;  // 100MHz
end

initial begin
    $dumpfile("tb_sys.vcd");
    $dumpvars(0, tb_sys);
end

endmodule
