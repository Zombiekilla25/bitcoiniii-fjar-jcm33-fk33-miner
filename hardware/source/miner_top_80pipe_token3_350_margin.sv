module miner_top_80pipe_token3_350_margin(
    input wire clk_p,
    input wire clk_n
);
    localparam integer NUM_PIPES = 80;
    localparam integer PIPES_PER_BANK = 8;
    localparam integer NUM_BANKS = NUM_PIPES / PIPES_PER_BANK;
    localparam integer CAND_W = 296;

    wire clk200_raw, clk200;
    wire clkfb_mmcm, clkfb_buf;
    wire clk400_mmcm, clk400;
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
        // 200 MHz * 4.375 / 2.500 = 350 MHz.
        // The routed 370 MHz image had exactly 0.000 ns WNS; this
        // diagnostic build restores about 0.154 ns of period margin.
        .CLKFBOUT_MULT_F(4.375),
        .CLKOUT0_DIVIDE_F(2.500),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(clk200),
        .CLKFBIN(clkfb_buf),
        .RST(1'b0),
        .PWRDWN(1'b0),
        .CLKFBOUT(clkfb_mmcm),
        .CLKOUT0(clk400_mmcm),
        .LOCKED(mmcm_locked),
        .CLKOUT0B(),
        .CLKOUT1(), .CLKOUT1B(),
        .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6()
    );

    BUFG u_bufgfb(.I(clkfb_mmcm), .O(clkfb_buf));
    BUFG u_bufg400(.I(clk400_mmcm), .O(clk400));

    (* ASYNC_REG="TRUE" *) logic [2:0] lock_sync400 = 3'b000;
    logic [3:0] release400 = 4'b0000;
    logic reset400 = 1'b1;

    always_ff @(posedge clk400) begin
        lock_sync400 <= {lock_sync400[1:0], mmcm_locked};
        if (!lock_sync400[2])
            release400 <= 4'b0000;
        else
            release400 <= {release400[2:0], 1'b1};
        reset400 <= ~release400[3];
    end

    // ============================================================
    // 200 MHz VIO/control island.
    // ============================================================
    wire [255:0] vio_header0;
    wire [255:0] vio_header1;
    wire [95:0]  vio_header2;
    wire [255:0] vio_target;
    wire [9:0]   vio_control;

    logic [40:0]  vio_status_mailbox = '0;
    logic [255:0] vio_digest_mailbox = '0;
    logic [31:0]  vio_live_nonce = '0; // raw Gray batch counter

    vio_0 u_vio (
        .clk(clk200),
        .probe_in0(vio_status_mailbox),
        .probe_in1(vio_digest_mailbox),
        .probe_in2(vio_live_nonce),
        .probe_out0(vio_header0),
        .probe_out1(vio_header1),
        .probe_out2(vio_header2),
        .probe_out3(vio_target),
        .probe_out4(vio_control)
    );

    logic [607:0] header200 = '0;
    logic [255:0] target200 = '0;
    logic [7:0] job_tag200 = '0;
    logic job_seen200 = 1'b0;
    logic ack_seen200 = 1'b0;

    wire job_event200 = (vio_control[9] != job_seen200);
    wire ack_event200 = (vio_control[8] != ack_seen200);

    wire [871:0] job_bus200 = {job_tag200, target200, header200};
    wire [871:0] job_bus400;
    wire job_toggle400;

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(2), .INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0), .SRC_INPUT_REG(0), .WIDTH(872)
    ) u_job_bus_cdc (
        .src_clk(clk200), .src_in(job_bus200),
        .dest_clk(clk400), .dest_out(job_bus400)
    );

    xpm_cdc_single #(
        .DEST_SYNC_FF(3), .INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0), .SRC_INPUT_REG(0)
    ) u_job_toggle_cdc (
        .src_clk(clk200), .src_in(job_seen200),
        .dest_clk(clk400), .dest_out(job_toggle400)
    );

    // ============================================================
    // 350 MHz TOKEN3 hash island.
    // ============================================================
    // Ten local 8-pipe banks. These replicas deliberately break the
    // huge global header/base/tag/target/start fanout that dominated the
    // previous 64-pipe route.
    (* KEEP="TRUE", DONT_TOUCH="TRUE" *) logic [607:0] bank_header400 [0:NUM_BANKS-1];
    (* KEEP="TRUE", DONT_TOUCH="TRUE" *) logic [31:0]  bank_base400 [0:NUM_BANKS-1];
    (* KEEP="TRUE", DONT_TOUCH="TRUE" *) logic [7:0]   bank_active_tag400 [0:NUM_BANKS-1];
    (* KEEP="TRUE", DONT_TOUCH="TRUE" *) logic [7:0]   bank_batch_tag400 [0:NUM_BANKS-1];
    (* KEEP="TRUE", DONT_TOUCH="TRUE" *) logic [15:0]  target_prefix400 [0:NUM_BANKS-1];

    logic last_job400 = 1'b0;
    logic job_pending400 = 1'b0;
    logic active_job400 = 1'b0;

    logic [31:0] batch_count400 = 32'd0;

    logic start_batch400 = 1'b0;
    (* KEEP="TRUE", DONT_TOUCH="TRUE" *) logic [NUM_BANKS-1:0] start_group400 = '0;

    integer bank_k;
    always_ff @(posedge clk400) begin
        for (bank_k=0; bank_k<NUM_BANKS; bank_k=bank_k+1)
            start_group400[bank_k] <= start_batch400;
    end

    localparam logic [1:0] SCH_IDLE      = 2'd0;
    localparam logic [1:0] SCH_WAIT_BUSY = 2'd1;
    localparam logic [1:0] SCH_RUN       = 2'd2;
    logic [1:0] sched_state400 = SCH_IDLE;

    wire [NUM_PIPES-1:0] pipe_busy;
    wire [NUM_PIPES-1:0] result_valid;
    wire [1:0] result_ctx [0:NUM_PIPES-1];
    wire [31:0] result_nonce [0:NUM_PIPES-1];
    wire [255:0] result_digest [0:NUM_PIPES-1];

    function automatic [639:0] make_header(
        input [607:0] prefix,
        input [31:0] nonce
    );
        logic [639:0] h;
        begin
            h = 640'd0;
            h[607:0] = prefix;
            h[615:608] = nonce[7:0];
            h[623:616] = nonce[15:8];
            h[631:624] = nonce[23:16];
            h[639:632] = nonce[31:24];
            make_header = h;
        end
    endfunction

    function automatic [255:0] reverse_bytes256(input [255:0] x);
        integer q;
        begin
            for (q=0; q<32; q=q+1)
                reverse_bytes256[q*8 +: 8] =
                    x[(31-q)*8 +: 8];
        end
    endfunction

    genvar p;
    generate
        for (p=0; p<NUM_PIPES; p=p+1) begin : PIPE_ARRAY
            localparam integer BANK = p / PIPES_PER_BANK;
            localparam integer PIPE_IN_BANK = p % PIPES_PER_BANK;
            localparam integer BASE_OFF = PIPE_IN_BANK * 3;

            // Per-pipe reset staging prevents one top-level reset net from
            // directly reaching the core's thousands of reset/CE loads.
            (* KEEP="TRUE", DONT_TOUCH="TRUE" *) logic pipe_reset400 = 1'b1;
            always_ff @(posedge clk400)
                pipe_reset400 <= reset400;

            // bank_base400 advances only in multiples of 256.
            // Therefore [31:8] is the batch number and the complete
            // low byte is a compile-time constant derived from pipe/context.
            // This removes the 32-bit carry chains from the pipe inputs.
            localparam logic [7:0] NONCE_LO0 = (p * 3) + 0;
            localparam logic [7:0] NONCE_LO1 = (p * 3) + 1;
            localparam logic [7:0] NONCE_LO2 = (p * 3) + 2;
            wire [31:0] n0 = {bank_base400[BANK][31:8], NONCE_LO0};
            wire [31:0] n1 = {bank_base400[BANK][31:8], NONCE_LO1};
            wire [31:0] n2 = {bank_base400[BANK][31:8], NONCE_LO2};

            (* DONT_TOUCH="TRUE" *)
            sha3t_token4_core u_pipe (
                .clk(clk400),
                .reset(pipe_reset400),
                .start(start_group400[BANK]),

                .header0(make_header(bank_header400[BANK], n0)),
                .header1(make_header(bank_header400[BANK], n1)),
                .header2(make_header(bank_header400[BANK], n2)),
                .header3(640'd0),

                .nonce0(n0), .nonce1(n1),
                .nonce2(n2), .nonce3(32'd0),

                .busy(pipe_busy[p]),
                .result_valid(result_valid[p]),
                .result_ctx(result_ctx[p]),
                .result_nonce(result_nonce[p]),
                .result_digest(result_digest[p])
            );
        end
    endgenerate

    wire batch_busy400 = pipe_busy[0];
    wire job_event400 = (job_toggle400 != last_job400);

    // ============================================================
    // Sparse candidate mailboxes.
    //
    // Unified per-pipe result output means there is no 4-way 256-bit
    // result mux anymore. A 16-bit target prefix is enough to slash
    // traffic while keeping the hash-domain compare extremely small.
    // Every true share necessarily passes:
    //    hash_top16 <= target_top16
    // ============================================================
    logic [CAND_W-1:0] candidate_hold400 [0:NUM_PIPES-1];
    logic [NUM_PIPES-1:0] candidate_toggle400 = '0;

    integer i;
    integer b;
    always_ff @(posedge clk400) begin
        start_batch400 <= 1'b0;

        if (reset400) begin
            last_job400 <= 1'b0;
            job_pending400 <= 1'b0;
            active_job400 <= 1'b0;
            batch_count400 <= 32'd0;
            sched_state400 <= SCH_IDLE;
            candidate_toggle400 <= '0;
            for (b=0; b<NUM_BANKS; b=b+1) begin
                bank_header400[b] <= '0;
                bank_base400[b] <= b * (PIPES_PER_BANK * 3);
                bank_active_tag400[b] <= '0;
                bank_batch_tag400[b] <= '0;
                target_prefix400[b] <= 16'd0;
            end
        end else begin
            if (job_event400) begin
                last_job400 <= job_toggle400;
                for (b=0; b<NUM_BANKS; b=b+1) begin
                    bank_header400[b] <= job_bus400[607:0];
                    bank_active_tag400[b] <= job_bus400[871:864];
                    target_prefix400[b] <= job_bus400[863:848];
                end

                job_pending400 <= 1'b1;
                active_job400 <= 1'b0;
            end else begin
                case (sched_state400)
                    SCH_IDLE: begin
                        if (job_pending400 && !batch_busy400) begin
                            batch_count400 <= 32'd0;
                            for (b=0; b<NUM_BANKS; b=b+1)
                                bank_base400[b] <= b * (PIPES_PER_BANK * 3);
                            job_pending400 <= 1'b0;
                            active_job400 <= 1'b1;
                        end else if (active_job400 && !batch_busy400) begin
                            for (b=0; b<NUM_BANKS; b=b+1)
                                bank_batch_tag400[b] <= bank_active_tag400[b];
                            start_batch400 <= 1'b1;
                            sched_state400 <= SCH_WAIT_BUSY;
                        end
                    end

                    SCH_WAIT_BUSY: begin
                        if (batch_busy400)
                            sched_state400 <= SCH_RUN;
                    end

                    SCH_RUN: begin
                        if (!batch_busy400) begin
                            if (!job_pending400) begin
                                for (b=0; b<NUM_BANKS; b=b+1)
                                    bank_base400[b] <= bank_base400[b] + 32'd256;
                                batch_count400 <= batch_count400 + 1'b1;
                            end
                            sched_state400 <= SCH_IDLE;
                        end
                    end

                    default: sched_state400 <= SCH_IDLE;
                endcase
            end

            for (i=0; i<NUM_PIPES; i=i+1) begin
                if (result_valid[i] &&
                    (reverse_bytes256(result_digest[i])[255:240] <=
                     target_prefix400[i/PIPES_PER_BANK])) begin
                    candidate_hold400[i] <= {
                        bank_batch_tag400[i/PIPES_PER_BANK],
                        result_nonce[i],
                        result_digest[i]
                    };
                    candidate_toggle400[i] <=
                        ~candidate_toggle400[i];
                end
            end
        end
    end

    // ============================================================
    // 80 sparse mailboxes cross to 200 MHz.
    // ============================================================
    wire [CAND_W-1:0] candidate_bus200 [0:NUM_PIPES-1];
    wire [NUM_PIPES-1:0] candidate_toggle200;

    genvar cdc_i;
    generate
        for (cdc_i=0; cdc_i<NUM_PIPES; cdc_i=cdc_i+1) begin : CAND_CDC
            xpm_cdc_array_single #(
                .DEST_SYNC_FF(2), .INIT_SYNC_FF(1),
                .SIM_ASSERT_CHK(0), .SRC_INPUT_REG(0),
                .WIDTH(CAND_W)
            ) u_candidate_bus_cdc (
                .src_clk(clk400),
                .src_in(candidate_hold400[cdc_i]),
                .dest_clk(clk200),
                .dest_out(candidate_bus200[cdc_i])
            );

            xpm_cdc_single #(
                .DEST_SYNC_FF(3), .INIT_SYNC_FF(1),
                .SIM_ASSERT_CHK(0), .SRC_INPUT_REG(0)
            ) u_candidate_toggle_cdc (
                .src_clk(clk400),
                .src_in(candidate_toggle400[cdc_i]),
                .dest_clk(clk200),
                .dest_out(candidate_toggle200[cdc_i])
            );
        end
    endgenerate

    // Progress remains Gray-coded inside the FPGA.
    wire [31:0] batch_gray400 =
        batch_count400 ^ (batch_count400 >> 1);
    wire [31:0] batch_gray200;

    xpm_cdc_array_single #(
        .DEST_SYNC_FF(2), .INIT_SYNC_FF(1),
        .SIM_ASSERT_CHK(0), .SRC_INPUT_REG(0), .WIDTH(32)
    ) u_batch_gray_cdc (
        .src_clk(clk400), .src_in(batch_gray400),
        .dest_clk(clk200), .dest_out(batch_gray200)
    );

    // ============================================================
    // 200 MHz full-target checker.
    // ============================================================
    logic [NUM_PIPES-1:0] seen_candidate_toggle200 = '0;
    logic [6:0] scan_index200 = 7'd0;
    logic scan_valid200 = 1'b0;
    logic [CAND_W-1:0] scan_result200 = '0;

    wire [255:0] scan_hash_ordered =
        reverse_bytes256(scan_result200[255:0]);

    wire scan_pass200 =
        scan_valid200 &&
        (scan_result200[295:288] == job_tag200) &&
        (scan_hash_ordered <= target200);

    logic share_pending200 = 1'b0;
    logic [31:0] found_nonce200 = '0;
    logic [255:0] found_digest200 = '0;
    logic [7:0] found_tag200 = '0;

    always_ff @(posedge clk200) begin
        if (job_event200) begin
            header200[255:0]   <= vio_header0;
            header200[511:256] <= vio_header1;
            header200[607:512] <= vio_header2;
            target200 <= vio_target;
            job_tag200 <= vio_control[7:0];
            job_seen200 <= vio_control[9];

            seen_candidate_toggle200 <= candidate_toggle200;
            scan_index200 <= 7'd0;
            scan_valid200 <= 1'b0;
            share_pending200 <= 1'b0;
        end else begin
            if (ack_event200) begin
                ack_seen200 <= vio_control[8];
                share_pending200 <= 1'b0;
            end

            if (scan_pass200 && !share_pending200) begin
                share_pending200 <= 1'b1;
                found_tag200 <= scan_result200[295:288];
                found_nonce200 <= scan_result200[287:256];
                found_digest200 <= scan_result200[255:0];
                scan_valid200 <= 1'b0;
            end else if (!share_pending200 || ack_event200) begin
                if (candidate_toggle200[scan_index200] !=
                    seen_candidate_toggle200[scan_index200]) begin
                    scan_result200 <= candidate_bus200[scan_index200];
                    seen_candidate_toggle200[scan_index200] <=
                        candidate_toggle200[scan_index200];
                    scan_valid200 <= 1'b1;
                end else begin
                    scan_valid200 <= 1'b0;
                end

                if (scan_index200 == 7'd79)
                    scan_index200 <= 7'd0;
                else
                    scan_index200 <= scan_index200 + 1'b1;
            end else begin
                scan_valid200 <= 1'b0;
            end
        end

        // Dedicated VIO mailbox registers.
        vio_status_mailbox <= {
            share_pending200,
            found_tag200,
            found_nonce200
        };
        vio_digest_mailbox <= found_digest200;
        vio_live_nonce <= batch_gray200;
    end

endmodule
