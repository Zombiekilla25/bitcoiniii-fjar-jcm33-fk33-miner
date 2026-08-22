`timescale 1ns/1ps

module tb_sha3t_ii1_miner_engine;
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic job_toggle = 1'b0;
    logic [871:0] job_bus = '0;

    wire [295:0] candidate_hold;
    wire candidate_toggle;
    wire [31:0] progress_gray;

    localparam logic [607:0] TEST_HEADER =
        608'h1a6a4d806a83773fd140fa88fc9159f51aaedd64c7990e4e99406e7155e97b1c59956cb63b0cb64700000000d72100000fd3c425fabaa7c8ab744ee3dac14d205e432fbda56d4d3320001000;

    // Python hashlib SHA3T result for TEST_HEADER || nonce 0 (little-endian).
    localparam logic [255:0] NONCE0_RAW_DIGEST =
        256'hbc3c2f6f9f5fb998831a4b414a487f844b3402c7632a075c8cb039d5802195f7;

    integer cycles = 0;
    logic previous_toggle = 1'b0;

    always #1.0 clk = ~clk;

    sha3t_ii1_miner_engine dut (
        .clk(clk),
        .reset(reset),
        .job_toggle(job_toggle),
        .job_bus(job_bus),
        .candidate_hold(candidate_hold),
        .candidate_toggle(candidate_toggle),
        .progress_gray(progress_gray)
    );

    always @(posedge clk) begin
        cycles = cycles + 1;
        #0.1;

        if (candidate_toggle != previous_toggle) begin
            if (candidate_hold[295:288] !== 8'h5a)
                $fatal(1, "ENGINE FAIL tag=%02x", candidate_hold[295:288]);

            if (candidate_hold[287:256] !== 32'd0)
                $fatal(1, "ENGINE FAIL first_nonce=%08x",
                       candidate_hold[287:256]);

            if (candidate_hold[255:0] !== NONCE0_RAW_DIGEST)
                $fatal(1, "ENGINE FAIL raw_digest=%064x",
                       candidate_hold[255:0]);

            $display("SHA3T II1 RAW DIGEST ALL PASS cycle=%0d tag=%02x nonce=%08x digest=%064x",
                     cycles,
                     candidate_hold[295:288],
                     candidate_hold[287:256],
                     candidate_hold[255:0]);
            $finish;
        end

        previous_toggle = candidate_toggle;

        if (cycles > 270)
            $fatal(1, "SHA3T II1 MINER ENGINE TIMEOUT");
    end

    initial begin
        repeat (5) @(posedge clk);
        reset <= 1'b0;
        repeat (3) @(posedge clk);

        // Maximum target makes nonce zero the first candidate.
        job_bus <= {
            8'h5a,
            256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff,
            TEST_HEADER
        };
        job_toggle <= 1'b1;
    end
endmodule
