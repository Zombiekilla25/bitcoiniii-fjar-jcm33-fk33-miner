`timescale 1ns/1ps
module tb_token4;
    logic clk=0, reset=1, start=0;
    logic [639:0] h0,h1,h2,h3;
    wire busy, rv;
    wire [1:0] rctx;
    wire [31:0] rnonce;
    wire [255:0] rdigest;
    integer pass_count=0;
    integer unexpected_count=0;
    integer busy_cycles=0;
    logic busy_seen=0;

    always #1.25 clk=~clk; // 400 MHz

    sha3t_token4_core dut(
        .clk(clk),.reset(reset),.start(start),
        .header0(h0),.header1(h1),.header2(h2),.header3(h3),
        .nonce0(32'd0),.nonce1(32'd1),.nonce2(32'd2),.nonce3(32'd3),
        .busy(busy),
        .result_valid(rv),.result_ctx(rctx),
        .result_nonce(rnonce),.result_digest(rdigest)
    );

    always @(posedge clk) begin
        if (busy) begin
            busy_seen <= 1'b1;
            busy_cycles <= busy_cycles + 1;
        end

        if (rv) begin
            case (rnonce)
                32'd0: begin
                    $display("NONCE0 DIGEST=%064x",rdigest);
                    if(rdigest===256'hbc3c2f6f9f5fb998831a4b414a487f844b3402c7632a075c8cb039d5802195f7) begin $display("NONCE0 PASS"); pass_count=pass_count+1; end
                    else $display("NONCE0 FAIL");
                end
                32'd1: begin
                    $display("NONCE1 DIGEST=%064x",rdigest);
                    if(rdigest===256'h45c4597cf3f1eb2f3746e52bd45581a8849fd054e825cf28d247c6e3f55da4b6) begin $display("NONCE1 PASS"); pass_count=pass_count+1; end
                    else $display("NONCE1 FAIL");
                end
                32'd2: begin
                    $display("NONCE2 DIGEST=%064x",rdigest);
                    if(rdigest===256'h6de6e2388ed49919ba724ce2fb443eb00fea2612fdebfb342e1301a7c92fbada) begin $display("NONCE2 PASS"); pass_count=pass_count+1; end
                    else $display("NONCE2 FAIL");
                end
                32'd3: begin
                    begin
                    unexpected_count=unexpected_count+1;
                    $display("UNEXPECTED NONCE3/CTX3 RESULT DIGEST=%064x",rdigest);
                    if(rdigest===256'hb7e86b6de4fe3b20de2042e591c7f5ba09997e597847383f00138d5e436497ab) begin $display("UNEXPECTED NONCE3 MATCH"); pass_count=pass_count+1; end
                    else $display("UNEXPECTED NONCE3 RESULT");
                end
                end
                default: begin unexpected_count=unexpected_count+1; $display("UNEXPECTED NONCE=%08x",rnonce); end
            endcase
        end
    end

    initial begin
        h0=640'h000000001a6a4d806a83773fd140fa88fc9159f51aaedd64c7990e4e99406e7155e97b1c59956cb63b0cb64700000000d72100000fd3c425fabaa7c8ab744ee3dac14d205e432fbda56d4d3320001000;
        h1=640'h000000011a6a4d806a83773fd140fa88fc9159f51aaedd64c7990e4e99406e7155e97b1c59956cb63b0cb64700000000d72100000fd3c425fabaa7c8ab744ee3dac14d205e432fbda56d4d3320001000;
        h2=640'h000000021a6a4d806a83773fd140fa88fc9159f51aaedd64c7990e4e99406e7155e97b1c59956cb63b0cb64700000000d72100000fd3c425fabaa7c8ab744ee3dac14d205e432fbda56d4d3320001000;
        h3=640'h000000031a6a4d806a83773fd140fa88fc9159f51aaedd64c7990e4e99406e7155e97b1c59956cb63b0cb64700000000d72100000fd3c425fabaa7c8ab744ee3dac14d205e432fbda56d4d3320001000;

        repeat(5) @(posedge clk);
        reset<=0;
        repeat(2) @(posedge clk);
        start<=1;
        @(posedge clk);
        start<=0;

        // IMPORTANT: busy is asserted by the DUT using a nonblocking
        // assignment on this same clock edge. Wait for the assertion
        // first, otherwise wait(!busy) can observe the old busy=0 and
        // terminate the simulation before any SHA3t result exists.
        wait(busy === 1'b1);
        wait(busy === 1'b0);
        repeat(10) @(posedge clk);

        $display("TOKEN3 BUSY_CYCLES=%0d", busy_cycles);
        if(pass_count==3 && unexpected_count==0 && busy_seen)
            $display("TOKEN3 ALL PASS");
        else
            $display("TOKEN3 FAIL pass_count=%0d unexpected_count=%0d busy_seen=%0d",
                     pass_count, unexpected_count, busy_seen);
        $finish;
    end
endmodule
