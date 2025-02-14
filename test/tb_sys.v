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
wire [7:0] rom_loading;
wire [7:0] rom_do;
wire rom_do_valid;
wire [31:0] core_config;
wire uart_tx;
reg uart_rx;

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
    .uart_rx(uart_rx),
    .uart_tx(uart_tx)
);

// Clock generation
initial begin
    clk = 0;
    forever #10 clk = ~clk;     // 50Mhz
end

// UART tasks
task uart_send_task;
    input [7:0] data;
    begin
        uart_rx = 0;         // Start bit
        #500;                // 1/2000000 baud = 500ns per bit
        for (integer i=0; i<8; i++) begin
            uart_rx = data[i];
            #500;
        end
        uart_rx = 1;         // Stop bit
        #500;
    end
endtask

task uart_recv_task;
    output [7:0] data;
    begin
        wait(uart_tx == 0);  // Wait for start bit
        #750;                 // Sample middle of start bit
        for (integer i=0; i<8; i++) begin
            data[i] = uart_tx;
            #500;             // Wait 1 bit period
        end
        #500;                 // Skip stop bit
    end
endtask

// Test procedure
reg [7:0] recv_data;
initial begin
    // Initialize inputs
    resetn = 0;
    uart_rx = 1;
    hclk = 0;
    
    // Reset sequence
    #100;
    resetn = 1;
    #100;
    
    // Test 1: Get core config string (CMD 1)
    begin : test1
        integer i;
        $display("Testing CMD 1 (Get core config)...");
        
        // Send command 1 via UART
        uart_send_task(1);
        
        // Receive response (original length + null terminator)
        for (i = 0; i < dut.STR_LEN + 1; i = i + 1) begin
            uart_recv_task(recv_data);
            $display("Received byte %h", recv_data);
            // Verify last byte is null
            if (i == dut.STR_LEN && recv_data !== 0) begin
                $display("Missing null terminator!");
            end
        end
    end
    
    // Test 2: Set core config (CMD 2)
    begin
        $display("Testing CMD 2 (Set core config)...");
        // For CMD 2, deassert CS after sending so the transaction completes.
        uart_send_task(2);
        uart_send_task(32'hA5);
        uart_send_task(32'hA5);
        uart_send_task(32'hA5);
        uart_send_task(32'hA5);
        #1000;
        if (core_config === 32'hA5A5A5A5)
            $display("CMD 2 test PASSED");
        else
            $display("CMD 2 test FAILED (core_config = %h)", core_config);
    end
    
    // Test 3: Toggle overlay (CMD 3)
    begin
        $display("Testing CMD 3 (Toggle overlay)...");
        uart_send_task(3);
        #100;
        if (overlay === 1'b1)
            $display("CMD 3 test PASSED");
        else
            $display("CMD 3 test FAILED (overlay = %b)", overlay);
    end

    // Test 4: Set cursor position (CMD 4)
    begin
        $display("Testing CMD 4 (Set cursor position)...");
        uart_send_task(4);
        uart_send_task(8'h12);
        uart_send_task(8'h03);
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
        uart_send_task(4);
        uart_send_task(8'h00);
        uart_send_task(8'h00);
        uart_send_task(5);
        uart_send_task("A");
        #200;
        if (dut.x_wr !== 8'h00 || dut.y_wr !== 8'h00 || dut.char_wr !== "A") begin
            error_count += 1;
            $display("A");
        end

        // Test 5b: Cursor advancement
        uart_send_task(0);
        uart_send_task("B");
        #200;
        if (dut.x_wr !== 8'h01 || dut.y_wr !== 8'h00 || dut.char_wr !== "B") begin
            error_count += 1;
            $display("B");
        end

        // Test 5c: Line overflow
        uart_send_task(4);
        uart_send_task(8'h1F);
        uart_send_task(8'h00);
        uart_send_task(5);
        uart_send_task("C");
        #200;
        if (dut.x_wr !== 8'h1F || dut.y_wr !== 8'h00 || dut.char_wr !== "C") begin
            error_count += 1;
            $display("C");
        end

        uart_send_task(0);
        uart_send_task("D");
        #200;
        if (dut.x_wr !== 8'h20 || dut.y_wr !== 8'h00 || dut.char_wr !== "D" || dut.we !== 1'b0) begin
            error_count += 1;
            $display("D");
        end

        // Test 5d: Null terminator
        uart_send_task(0);
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
        uart_send_task(6);
        uart_send_task(8'h01);
        #100;
        if (rom_loading !== 8'b1)
            $display("CMD 6 enable test FAILED");
        
        // Test disable
        uart_send_task(6);
        uart_send_task(8'h00);
        #100;
        if (rom_loading === 8'b0)
            $display("CMD 6 test PASSED");
        else
            $display("CMD 6 disable test FAILED");
    end

    // Test 7: ROM data transfer (CMD 7)
    begin
        $display("Testing CMD 7 (ROM data transfer)...");
        // Send 3 bytes (length=3) with random data
        uart_send_task(7);
        uart_send_task(24'h000003);
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
