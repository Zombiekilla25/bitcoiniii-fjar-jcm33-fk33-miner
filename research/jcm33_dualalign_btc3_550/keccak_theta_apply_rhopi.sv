module keccak_theta_apply_rhopi(
    input  logic [1599:0] state_in,
    input  logic [319:0]  c_in,
    output logic [1599:0] b_out
);
    logic [63:0] A [0:24];
    logic [63:0] C [0:4];
    logic [63:0] D [0:4];
    logic [63:0] T [0:24];
    logic [63:0] B [0:24];
    integer x, y, i, nx, ny;

    function automatic [63:0] rol1(input [63:0] v);
        begin
            rol1 = {v[62:0], v[63]};
        end
    endfunction

    function automatic [63:0] rol64(input [63:0] v, input integer n);
        begin
            if (n == 0)
                rol64 = v;
            else
                rol64 = (v << n) | (v >> (64-n));
        end
    endfunction

    function automatic integer rho_offset(input integer idx);
        begin
            case (idx)
                 0: rho_offset=0;   1: rho_offset=1;   2: rho_offset=62;  3: rho_offset=28;  4: rho_offset=27;
                 5: rho_offset=36;  6: rho_offset=44;  7: rho_offset=6;   8: rho_offset=55;  9: rho_offset=20;
                10: rho_offset=3;  11: rho_offset=10; 12: rho_offset=43; 13: rho_offset=25; 14: rho_offset=39;
                15: rho_offset=41; 16: rho_offset=45; 17: rho_offset=15; 18: rho_offset=21; 19: rho_offset=8;
                20: rho_offset=18; 21: rho_offset=2;  22: rho_offset=61; 23: rho_offset=56; 24: rho_offset=14;
                default: rho_offset=0;
            endcase
        end
    endfunction

    always_comb begin
        for (i=0; i<25; i=i+1)
            A[i] = state_in[i*64 +: 64];

        for (x=0; x<5; x=x+1)
            C[x] = c_in[x*64 +: 64];

        for (x=0; x<5; x=x+1)
            D[x] = C[(x+4)%5] ^ rol1(C[(x+1)%5]);

        for (y=0; y<5; y=y+1)
            for (x=0; x<5; x=x+1)
                T[x+5*y] = A[x+5*y] ^ D[x];

        for (i=0; i<25; i=i+1)
            B[i] = 64'h0;

        for (y=0; y<5; y=y+1) begin
            for (x=0; x<5; x=x+1) begin
                nx = y;
                ny = (2*x + 3*y) % 5;
                B[nx + 5*ny] =
                    rol64(T[x+5*y], rho_offset(x+5*y));
            end
        end

        for (i=0; i<25; i=i+1)
            b_out[i*64 +: 64] = B[i];
    end
endmodule
