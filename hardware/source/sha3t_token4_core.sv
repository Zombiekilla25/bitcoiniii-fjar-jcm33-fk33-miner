module sha3t_token4_core(
    input  logic         clk,
    input  logic         reset,
    input  logic         start,

    input  logic [639:0] header0,
    input  logic [639:0] header1,
    input  logic [639:0] header2,
    input  logic [639:0] header3,

    input  logic [31:0]  nonce0,
    input  logic [31:0]  nonce1,
    input  logic [31:0]  nonce2,
    input  logic [31:0]  nonce3,

    output logic         busy,

    output logic         result_valid,
    output logic [1:0]   result_ctx,
    output logic [31:0]  result_nonce,
    output logic [255:0] result_digest
);

    // TOKEN3 implementation.
    //
    // Interface intentionally remains compatible with TOKEN4 for now.
    // header3/nonce3 are unused.  Three circulating contexts are exactly
    // sufficient to keep a 3-stage recurrence pipeline full.

    // Stage 1: original state + theta column parity.
    logic          s1_valid;
    logic [1599:0] s1_state;
    logic [319:0]  s1_c;
    logic [1:0]    s1_ctx;
    logic [4:0]    s1_round;
    logic [1:0]    s1_perm;
    logic [31:0]   s1_nonce;

    // Stage 2: theta applied + rho/pi.
    logic          s2_valid;
    logic [1599:0] s2_b;
    logic [1:0]    s2_ctx;
    logic [4:0]    s2_round;
    logic [1:0]    s2_perm;
    logic [31:0]   s2_nonce;

    // Stage 3: chi + iota.  This is the completed Keccak round state.
    logic          s3_valid;
    logic [1599:0] s3_state;
    logic [1:0]    s3_ctx;
    logic [4:0]    s3_round;
    logic [1:0]    s3_perm;
    logic [31:0]   s3_nonce;

    logic [2:0] load_count;
    logic       loading;
    logic [2:0] active_tokens;

    logic [1599:0] source_state;
    logic [1:0]    source_ctx;
    logic [4:0]    source_round;
    logic [1:0]    source_perm;
    logic [31:0]   source_nonce;
    logic          source_valid;

    logic [319:0]  parity_comb;
    logic [1599:0] rhopi_comb;
    logic [1599:0] chi_comb;
    logic [1599:0] iota_comb;

    function automatic [1599:0] init80(input [639:0] msg);
        logic [1599:0] t;
        begin
            t = '0;
            t[639:0] = msg;
            t[647:640] = 8'h06;
            t[1087:1080] = 8'h80;
            init80 = t;
        end
    endfunction

    function automatic [1599:0] init32(input [255:0] msg);
        logic [1599:0] t;
        begin
            t = '0;
            t[255:0] = msg;
            t[263:256] = 8'h06;
            t[1087:1080] = 8'h80;
            init32 = t;
        end
    endfunction

    function automatic [255:0] reverse_bytes256(input [255:0] v);
        integer i;
        begin
            for (i=0; i<32; i=i+1)
                reverse_bytes256[(31-i)*8 +: 8] = v[i*8 +: 8];
        end
    endfunction

    // Three startup clocks inject contexts 0,1,2.
    //
    // After startup, the completed Stage-3 token feeds directly back
    // into Stage 1.  Round 23 either begins the next SHA3 permutation
    // or retires the final SHA3t result.
    always_comb begin
        source_valid = 1'b0;
        source_state = '0;
        source_ctx   = '0;
        source_round = '0;
        source_perm  = '0;
        source_nonce = '0;

        if (loading) begin
            source_valid = 1'b1;
            source_round = 5'd0;
            source_perm  = 2'd0;

            case (load_count)
                3'd0: begin
                    source_state = init80(header0);
                    source_ctx   = 2'd0;
                    source_nonce = nonce0;
                end

                3'd1: begin
                    source_state = init80(header1);
                    source_ctx   = 2'd1;
                    source_nonce = nonce1;
                end

                default: begin
                    source_state = init80(header2);
                    source_ctx   = 2'd2;
                    source_nonce = nonce2;
                end
            endcase
        end else if (s3_valid) begin
            source_ctx   = s3_ctx;
            source_nonce = s3_nonce;

            if (s3_round == 5'd23) begin
                if (s3_perm != 2'd2) begin
                    source_valid = 1'b1;
                    source_state = init32(s3_state[255:0]);
                    source_round = 5'd0;
                    source_perm  = s3_perm + 1'b1;
                end
                // perm==2 / round==23 is the final SHA3t digest.
                // Do not feed that token back.
            end else begin
                source_valid = 1'b1;
                source_state = s3_state;
                source_round = s3_round + 1'b1;
                source_perm  = s3_perm;
            end
        end
    end

    keccak_theta_parity u_parity (
        .state_in(source_state),
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

    // Iota is fused into Stage 3.
    // It adds only the round-constant XOR after chi.
    keccak_iota u_iota (
        .chi_in(chi_comb),
        .round_idx(s2_round),
        .state_out(iota_comb)
    );

    always_ff @(posedge clk) begin
        result_valid <= 1'b0;

        // Payload registers clock every cycle; valid bits determine meaning.
        // Keep the no-CE structure that improved our 350-MHz route.

        s3_state <= iota_comb;
        s3_ctx   <= s2_ctx;
        s3_round <= s2_round;
        s3_perm  <= s2_perm;
        s3_nonce <= s2_nonce;

        s2_b     <= rhopi_comb;
        s2_ctx   <= s1_ctx;
        s2_round <= s1_round;
        s2_perm  <= s1_perm;
        s2_nonce <= s1_nonce;

        s1_state <= source_state;
        s1_c     <= parity_comb;
        s1_ctx   <= source_ctx;
        s1_round <= source_round;
        s1_perm  <= source_perm;
        s1_nonce <= source_nonce;

        if (reset) begin
            busy          <= 1'b0;
            loading       <= 1'b0;
            load_count    <= 3'd0;
            active_tokens <= 3'd0;

            s1_valid <= 1'b0;
            s2_valid <= 1'b0;
            s3_valid <= 1'b0;

        end else begin
            if (start && !busy) begin
                busy          <= 1'b1;
                loading       <= 1'b1;
                load_count    <= 3'd0;
                active_tokens <= 3'd3;

                s1_valid <= 1'b0;
                s2_valid <= 1'b0;
                s3_valid <= 1'b0;

            end else if (busy) begin

                // Final SHA3t permutation retirement.
                if (s3_valid &&
                    s3_round == 5'd23 &&
                    s3_perm  == 2'd2) begin

                    result_valid  <= 1'b1;
                    result_ctx    <= s3_ctx;
                    result_nonce  <= s3_nonce;
                    result_digest <= reverse_bytes256(s3_state[255:0]);

                    if (active_tokens == 3'd1) begin
                        active_tokens <= 3'd0;
                        busy          <= 1'b0;
                    end else begin
                        active_tokens <= active_tokens - 1'b1;
                    end
                end

                // Three-stage valid pipeline.
                s3_valid <= s2_valid;
                s2_valid <= s1_valid;
                s1_valid <= source_valid;

                // Exactly three startup tokens.
                if (loading) begin
                    if (load_count == 3'd2) begin
                        loading <= 1'b0;
                    end else begin
                        load_count <= load_count + 1'b1;
                    end
                end
            end
        end
    end

endmodule
