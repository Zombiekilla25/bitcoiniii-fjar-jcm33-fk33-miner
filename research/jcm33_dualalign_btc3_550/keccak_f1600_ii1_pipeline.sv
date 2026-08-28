module keccak_f1600_ii1_pipeline #(
    parameter integer META_W = 32
)(
    input  logic                  clk,
    input  logic                  reset,
    input  logic                  in_valid,
    input  logic [1599:0]         in_state,
    input  logic [META_W-1:0]     in_meta,
    output logic                  out_valid,
    output logic [1599:0]         out_state,
    output logic [META_W-1:0]     out_meta
);

    // Fully unrolled Keccak-f[1600] permutation.
    //
    // Each of the 24 rounds is split into the same three stages used by the
    // proven TOKEN3 recurrence core:
    //   1. theta column parity
    //   2. theta apply plus rho/pi
    //   3. chi plus iota
    //
    // Latency is 72 clocks.  Once filled, the initiation interval is one:
    // one independent state may enter and one completed state may leave on
    // every clock.

    wire [1599:0]     round_state [0:24];
    wire              round_valid [0:24];
    wire [META_W-1:0] round_meta  [0:24];

    assign round_state[0] = in_state;
    assign round_valid[0] = in_valid;
    assign round_meta[0]  = in_meta;

    genvar r;
    generate
        for (r = 0; r < 24; r = r + 1) begin : ROUND
            localparam logic [4:0] ROUND_INDEX = r;

            wire [319:0]  parity_comb;
            wire [1599:0] rhopi_comb;
            wire [1599:0] chi_comb;
            wire [1599:0] iota_comb;

            logic [1599:0] s1_state;
            logic [319:0]  s1_c;
            logic          s1_valid;
            logic [META_W-1:0] s1_meta;

            logic [1599:0] s2_b;
            logic          s2_valid;
            logic [META_W-1:0] s2_meta;

            logic [1599:0] s3_state;
            logic          s3_valid;
            logic [META_W-1:0] s3_meta;

            keccak_theta_parity u_parity (
                .state_in(round_state[r]),
                .c_out(parity_comb)
            );

            keccak_theta_apply_rhopi u_theta_rhopi (
                .state_in(s1_state),
                .c_in(s1_c),
                .b_out(rhopi_comb)
            );

            keccak_chi u_chi (
                .b_in(s2_b),
                .chi_out(chi_comb)
            );

            keccak_iota u_iota (
                .chi_in(chi_comb),
                .round_idx(ROUND_INDEX),
                .state_out(iota_comb)
            );

            // Payloads deliberately clock without enables or resets.  Only
            // the valid pipeline is reset; invalid payload values are ignored.
            // This avoids the high-fanout CE/reset structure that hurt the
            // timing of the original recurrence builds.
            always_ff @(posedge clk) begin
                s1_state <= round_state[r];
                s1_c     <= parity_comb;
                s1_meta  <= round_meta[r];

                s2_b     <= rhopi_comb;
                s2_meta  <= s1_meta;

                s3_state <= iota_comb;
                s3_meta  <= s2_meta;

                if (reset) begin
                    s1_valid <= 1'b0;
                    s2_valid <= 1'b0;
                    s3_valid <= 1'b0;
                end else begin
                    s1_valid <= round_valid[r];
                    s2_valid <= s1_valid;
                    s3_valid <= s2_valid;
                end
            end

            assign round_state[r+1] = s3_state;
            assign round_valid[r+1] = s3_valid;
            assign round_meta[r+1]  = s3_meta;
        end
    endgenerate

    assign out_state = round_state[24];
    assign out_valid = round_valid[24];
    assign out_meta  = round_meta[24];

endmodule
