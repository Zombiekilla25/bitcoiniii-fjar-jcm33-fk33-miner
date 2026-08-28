module sha3t_ii1_pipeline(
    input  logic         clk,
    input  logic         reset,
    input  logic         in_valid,
    input  logic [607:0] header_prefix,
    input  logic [31:0]  nonce,
    output logic         out_valid,
    output logic [31:0]  out_nonce,
    output logic [255:0] out_digest
);

    // FJAR/BC3 SHA3-256T is three SHA3-256 operations.  The three fully
    // unrolled Keccak pipelines below correspond to those three passes.
    // Total latency: 3 * 24 rounds * 3 stages/round = 216 clocks.
    // Steady-state initiation interval: one nonce per clock.

    function automatic [639:0] make_header(
        input [607:0] prefix,
        input [31:0] nonce_value
    );
        logic [639:0] h;
        begin
            h = 640'd0;
            h[607:0]   = prefix;
            h[615:608] = nonce_value[7:0];
            h[623:616] = nonce_value[15:8];
            h[631:624] = nonce_value[23:16];
            h[639:632] = nonce_value[31:24];
            make_header = h;
        end
    endfunction

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
            for (i = 0; i < 32; i = i + 1)
                reverse_bytes256[(31-i)*8 +: 8] = v[i*8 +: 8];
        end
    endfunction

    wire [1599:0] pass1_in_state =
        init80(make_header(header_prefix, nonce));

    wire          pass1_valid;
    wire [1599:0] pass1_state;
    wire [31:0]   pass1_nonce;

    wire          pass2_valid;
    wire [1599:0] pass2_state;
    wire [31:0]   pass2_nonce;

    wire          pass3_valid;
    wire [1599:0] pass3_state;
    wire [31:0]   pass3_nonce;

    keccak_f1600_ii1_pipeline #(.META_W(32)) u_pass1 (
        .clk(clk),
        .reset(reset),
        .in_valid(in_valid),
        .in_state(pass1_in_state),
        .in_meta(nonce),
        .out_valid(pass1_valid),
        .out_state(pass1_state),
        .out_meta(pass1_nonce)
    );

    keccak_f1600_ii1_pipeline #(.META_W(32)) u_pass2 (
        .clk(clk),
        .reset(reset),
        .in_valid(pass1_valid),
        .in_state(init32(pass1_state[255:0])),
        .in_meta(pass1_nonce),
        .out_valid(pass2_valid),
        .out_state(pass2_state),
        .out_meta(pass2_nonce)
    );

    keccak_f1600_ii1_pipeline #(.META_W(32)) u_pass3 (
        .clk(clk),
        .reset(reset),
        .in_valid(pass2_valid),
        .in_state(init32(pass2_state[255:0])),
        .in_meta(pass2_nonce),
        .out_valid(pass3_valid),
        .out_state(pass3_state),
        .out_meta(pass3_nonce)
    );

    assign out_valid  = pass3_valid;
    assign out_nonce  = pass3_nonce;
    assign out_digest = reverse_bytes256(pass3_state[255:0]);

endmodule
