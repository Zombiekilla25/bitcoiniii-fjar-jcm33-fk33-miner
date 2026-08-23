`timescale 1ns/1ps

module sha3t_ii1_miner_engine (
    input  logic         clk,
    input  logic         reset,
    input  logic         job_toggle,
    input  logic [871:0] job_bus,
    output logic [295:0] candidate_hold,
    output logic         candidate_toggle,
    output logic [31:0]  progress_gray
);
    logic         last_job = 1'b0;
    logic         active = 1'b0;
    logic [607:0] active_header = '0;
    logic [15:0]  target_prefix = '0;
    logic [7:0]   active_tag = '0;
    logic [31:0]  nonce_counter = '0;

    wire job_event = (job_toggle != last_job);
    wire pipeline_reset = reset || job_event;

    wire         result_valid;
    wire [31:0]  result_nonce;
    wire [255:0] result_digest_raw;

    function automatic [255:0] reverse_bytes256(input [255:0] value);
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                reverse_bytes256[i*8 +: 8] =
                    value[(31-i)*8 +: 8];
        end
    endfunction

    // The pipeline emits the raw digest byte sequence used by Python's
    // hashlib.sha3_256().  Only the target comparison uses the integer
    // byte order.  The candidate mailbox must preserve the raw sequence.
    wire [255:0] result_digest_ordered =
        reverse_bytes256(result_digest_raw);

    sha3t_ii1_pipeline u_pipeline (
        .clk(clk),
        .reset(pipeline_reset),
        .in_valid(active && !job_event && !reset),
        .header_prefix(active_header),
        .nonce(nonce_counter),
        .out_valid(result_valid),
        .out_nonce(result_nonce),
        .out_digest(result_digest_raw)
    );

    // Preserve the released worker's progress convention: a Gray-coded
    // counter representing completed 256-nonce regions.
    wire [31:0] progress_binary = {8'd0, nonce_counter[31:8]};

    always_comb begin
        progress_gray = progress_binary ^ (progress_binary >> 1);
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            last_job <= 1'b0;
            active <= 1'b0;
            active_header <= '0;
            target_prefix <= '0;
            active_tag <= '0;
            nonce_counter <= '0;
            candidate_hold <= '0;
            candidate_toggle <= 1'b0;
        end else if (job_event) begin
            // Capturing a new job also flushes the pipeline valid bits, so a
            // result from the previous job can never be tagged as the new job.
            last_job <= job_toggle;
            active_header <= job_bus[607:0];
            target_prefix <= job_bus[863:848];
            active_tag <= job_bus[871:864];
            nonce_counter <= 32'd0;
            active <= 1'b1;
        end else begin
            if (active)
                nonce_counter <= nonce_counter + 1'b1;

            // Prefix filtering reduces CDC traffic.  Every true full-target
            // share necessarily passes this ordered top-16 comparison.
            if (result_valid &&
                (result_digest_ordered[255:240] <= target_prefix)) begin
                candidate_hold <= {
                    active_tag,
                    result_nonce,
                    result_digest_raw
                };
                candidate_toggle <= ~candidate_toggle;
            end
        end
    end
endmodule
