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
        if (cmd > 0) 
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
    
    // Test 3: Toggle overlay (CMD 3)
    begin
        $display("Testing CMD 3 (Toggle overlay)...");
        spi_send_task(3, 8'h01, 0, 1); // Turn on overlay
        #100;
        if (overlay === 1'b1)
            $display("CMD 3 test PASSED");
        else
            $display("CMD 3 test FAILED (overlay = %b)", overlay);
    end

    // Test 4: Set cursor position (CMD 4)
    begin
        $display("Testing CMD 4 (Set cursor position)...");
        spi_send_task(4, {8'h12, 8'h03}, 0, 1); // X=0x12, Y=0x34
        #100;
        // Verify cursor position through x_wr/y_wr registers
        if (dut.cursor_x === 8'h12 && dut.cursor_y === 8'h03)
            $display("CMD 4 test PASSED");
        else
            $display("CMD 4 test FAILED (x_wr = %h, y_wr = %h, we = %b)", 
                    dut.x_wr, dut.y_wr, dut.we);
    end

    // Test 5: Display string (CMD 5)
    begin
        integer error_count = 0;
        $display("Testing CMD 5 (Display string)...");
        
        // Test 5a: Basic character writing
        spi_send_task(4, {8'h00, 8'h00}, 0, 1); // Set cursor to (0,0)
        #100;
        spi_send_task(5, "A", 0, 0);
        #200;
        if (dut.x_wr !== 8'h00 || dut.y_wr !== 8'h00 || dut.char_wr !== "A") begin
            error_count += 1;
            $display("A");
        end

        // Test 5b: Cursor advancement
        spi_send_task(0, "B", 0, 1);
        #200;
        if (dut.x_wr !== 8'h01 || dut.y_wr !== 8'h00 || dut.char_wr !== "B") begin
            error_count += 1;
            $display("B");
        end

        // Test 5c: Line overflow
        spi_send_task(4, {8'h1F, 8'h00}, 0, 1); // Set to column 31
        #100;
        spi_send_task(5, "C", 0, 0);
        #200;
        if (dut.x_wr !== 8'h1F || dut.y_wr !== 8'h00 || dut.char_wr !== "C") begin
            error_count += 1;
            $display("C");
        end

        spi_send_task(0, "D", 0, 0);
        #200;
        if (dut.x_wr !== 8'h20 || dut.y_wr !== 8'h00 || dut.char_wr !== "D" || dut.we !== 1'b0) begin
            error_count += 1;
            $display("D");
        end

        // Test 5d: Null terminator
        spi_send_task(0, 8'h00, 0, 1);
        #200;
        if (dut.we !== 1'b0) begin
            error_count += 1;
            $display("null");
        end

        // Final result
        if (error_count == 0)
            $display("CMD 5 test PASSED");
        else
            $display("CMD 5 test FAILED (%0d errors)", error_count);
    end

    // Test 6: Set ROM loading state (CMD 6)
    begin
        $display("Testing CMD 6 (ROM loading state)...");
        // Test enable
        spi_send_task(6, 8'h01, 0, 1);
        #100;
        if (rom_loading !== 1'b1)
            $display("CMD 6 enable test FAILED");
        
        // Test disable
        spi_send_task(6, 8'h00, 0, 1);
        #100;
        if (rom_loading === 1'b0)
            $display("CMD 6 test PASSED");
        else
            $display("CMD 6 disable test FAILED");
    end

    // Test 7: ROM data transfer (CMD 7)
    begin
        $display("Testing CMD 7 (ROM data transfer)...");
        // Send 3 bytes (length=3) with random data
        spi_send_task(7, 0, 24'h000003, 1);
        #1000;
        // Verify 3 bytes received with valid pulses
        if (dut.rom_remain === 24'h0)
            $display("CMD 7 test PASSED");
        else
            $display("CMD 7 test FAILED (rom_remain = %h)", dut.rom_remain);
    end

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
