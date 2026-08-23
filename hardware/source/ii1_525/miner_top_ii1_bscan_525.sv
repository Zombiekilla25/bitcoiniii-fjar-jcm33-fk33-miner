`timescale 1ns/1ps

module miner_top_ii1_bscan_525 (
    input wire clk_p,
    input wire clk_n
);
    localparam integer CAND_W = 296;

    wire clk200_raw, clk200;
    wire clkfb_mmcm, clkfb_buf;
    wire clk525_mmcm, clk525;
    wire mmcm_locked;

    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IBUF_LOW_PWR("FALSE")
    ) u_ibufds (
        .I(clk_p), .IB(clk_n), .O(clk200_raw)
    );

    BUFG u_bufg200(.I(clk200_raw), .O(clk200));

    MMCME4_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(5.000),
        .DIVCLK_DIVIDE(1),
        // 200 MHz * 5.5 / 2 = 525 MHz; VCO = 1000 MHz.
        .CLKFBOUT_MULT_F(5.250),
        .CLKOUT0_DIVIDE_F(2.000),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(clk200),
        .CLKFBIN(clkfb_buf),
        .RST(1'b0),
        .PWRDWN(1'b0),
        .CLKFBOUT(clkfb_mmcm),
        .CLKOUT0(clk525_mmcm),
        .LOCKED(mmcm_locked),
        .CLKOUT0B(),
        .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
    );

    BUFG u_bufgfb(.I(clkfb_mmcm), .O(clkfb_buf));
    BUFG u_bufg525(.I(clk525_mmcm), .O(clk525));

    (* ASYNC_REG="TRUE" *) logic [2:0] lock_sync525 = 3'b000;
    logic [3:0] release525 = 4'b0000;
    logic reset525 = 1'b1;

    always_ff @(posedge clk525) begin
        lock_sync525 <= {lock_sync525[1:0], mmcm_locked};
        if (!lock_sync525[2])
            release525 <= 4'b0000;
        else
            release525 <= {release525[2:0], 1'b1};
        reset525 <= ~release525[3];
    end

    // The exact released fleet transport is retained.  USER2 carries framed
    // jobs, USER1 carries framed shares, and USER3 exposes share-ready status.
    wire [607:0] bscan_job_header;
    wire [255:0] bscan_job_target;
    wire [7:0] bscan_job_tag;
    wire bscan_job_pulse;
    wire bscan_share_ready;

    logic bscan_share_valid = 1'b0;
    logic [7:0] bscan_share_tag = '0;
    logic [31:0] bscan_share_nonce = '0;
    logic [255:0] bscan_share_digest = '0;

    fk33_bscan_transport u_bscan_transport (
        .clk(clk200),
        .job_header(bscan_job_header),
        .job_target(bscan_job_target),
        .job_tag(bscan_job_tag),
        .job_pulse(bscan_job_pulse),
        .share_valid(bscan_share_valid),
        .share_tag(bscan_share_tag),
        .share_nonce(bscan_share_nonce),
        .share_digest(bscan_share_digest),
        .share_ready(bscan_share_ready)
    );

    logic [607:0] header200 = '0;
    logic [255:0] target200 = '0;
    logic [7:0] job_tag200 = '0;
    logic job_seen200 = 1'b0;

    wire [871:0] job_bus200 = {job_tag200, target200, header200};
    wire [871:0] job_bus525;
    wire job_toggle525;

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(2), .INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0), .SRC_INPUT_REG(0), .WIDTH(872)
    ) u_job_bus_cdc (
        .src_clk(clk200), .src_in(job_bus200),
        .dest_clk(clk525), .dest_out(job_bus525)
    );

    xpm_cdc_single #(
        .DEST_SYNC_FF(3), .INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0), .SRC_INPUT_REG(0)
    ) u_job_toggle_cdc (
        .src_clk(clk200), .src_in(job_seen200),
        .dest_clk(clk525), .dest_out(job_toggle525)
    );

    wire [CAND_W-1:0] candidate_hold525;
    wire candidate_toggle525;
    wire [31:0] progress_gray525;

    sha3t_ii1_miner_engine u_engine (
        .clk(clk525),
        .reset(reset525),
        .job_toggle(job_toggle525),
        .job_bus(job_bus525),
        .candidate_hold(candidate_hold525),
        .candidate_toggle(candidate_toggle525),
        .progress_gray(progress_gray525)
    );

    wire [CAND_W-1:0] candidate_bus200;
    wire candidate_toggle200;

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(2), .INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0), .SRC_INPUT_REG(0), .WIDTH(CAND_W)
    ) u_candidate_bus_cdc (
        .src_clk(clk525), .src_in(candidate_hold525),
        .dest_clk(clk200), .dest_out(candidate_bus200)
    );

    xpm_cdc_single #(
        .DEST_SYNC_FF(3), .INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0), .SRC_INPUT_REG(0)
    ) u_candidate_toggle_cdc (
        .src_clk(clk525), .src_in(candidate_toggle525),
        .dest_clk(clk200), .dest_out(candidate_toggle200)
    );

    function automatic [255:0] reverse_bytes256(input [255:0] value);
        integer i;
        begin
            for (i = 0; i < 32; i = i + 1)
                reverse_bytes256[i*8 +: 8] =
                    value[(31-i)*8 +: 8];
        end
    endfunction

    logic seen_candidate_toggle200 = 1'b0;
    logic scan_valid200 = 1'b0;
    logic [CAND_W-1:0] scan_result200 = '0;

    wire [255:0] scan_hash_ordered =
        reverse_bytes256(scan_result200[255:0]);

    wire scan_pass200 =
        scan_valid200 &&
        (scan_result200[295:288] == job_tag200) &&
        (scan_hash_ordered <= target200);

    always_ff @(posedge clk200) begin
        bscan_share_valid <= 1'b0;

        if (bscan_job_pulse) begin
            header200 <= bscan_job_header;
            target200 <= bscan_job_target;
            job_tag200 <= bscan_job_tag;
            job_seen200 <= ~job_seen200;

            // Discard any candidate crossing from the previous job.
            seen_candidate_toggle200 <= candidate_toggle200;
            scan_valid200 <= 1'b0;
        end else begin
            if (scan_pass200 && bscan_share_ready) begin
                bscan_share_tag <= scan_result200[295:288];
                bscan_share_nonce <= scan_result200[287:256];
                bscan_share_digest <= scan_result200[255:0];
                bscan_share_valid <= 1'b1;
                scan_valid200 <= 1'b0;
            end else if (!scan_pass200 && bscan_share_ready) begin
                if (candidate_toggle200 != seen_candidate_toggle200) begin
                    scan_result200 <= candidate_bus200;
                    seen_candidate_toggle200 <= candidate_toggle200;
                    scan_valid200 <= 1'b1;
                end else begin
                    scan_valid200 <= 1'b0;
                end
            end
        end
    end

    // Kept visible for implementation/debug reporting without adding a VIO.
    (* KEEP="TRUE" *) wire [31:0] progress_gray_debug = progress_gray525;

endmodule
