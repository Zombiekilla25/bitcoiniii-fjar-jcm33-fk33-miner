`timescale 1ns/1ps

// Small hardware canary for the complete framed transport.  It receives a
// normal 109-byte job payload and returns one normal 37-byte share payload:
//   tag    = received tag
//   nonce  = low 32 bits of received target
//   digest = low 256 bits of received header
//
// Because the share wire format emits digest[255:248] first, a host sending
// prefix bytes 00..4b should receive digest bytes 1f..00.  This deliberately
// exposes byte-order mistakes before the full miner is built.
module fk33_bscan_protocol_probe_top (
    input wire clk_p,
    input wire clk_n
);
    wire clk200_raw;
    wire clk200;

    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IBUF_LOW_PWR("FALSE")
    ) u_ibufds (
        .I(clk_p),
        .IB(clk_n),
        .O(clk200_raw)
    );

    BUFG u_bufg200 (
        .I(clk200_raw),
        .O(clk200)
    );

    wire [607:0] job_header;
    wire [255:0] job_target;
    wire [7:0] job_tag;
    wire job_pulse;
    wire share_ready;

    logic share_valid = 1'b0;
    logic [7:0] share_tag = '0;
    logic [31:0] share_nonce = '0;
    logic [255:0] share_digest = '0;

    fk33_bscan_transport u_transport (
        .clk(clk200),
        .job_header(job_header),
        .job_target(job_target),
        .job_tag(job_tag),
        .job_pulse(job_pulse),
        .share_valid(share_valid),
        .share_tag(share_tag),
        .share_nonce(share_nonce),
        .share_digest(share_digest),
        .share_ready(share_ready)
    );

    always_ff @(posedge clk200) begin
        share_valid <= 1'b0;
        if (job_pulse && share_ready) begin
            share_tag <= job_tag;
            share_nonce <= job_target[31:0];
            share_digest <= job_header[255:0];
            share_valid <= 1'b1;
        end
    end

endmodule
