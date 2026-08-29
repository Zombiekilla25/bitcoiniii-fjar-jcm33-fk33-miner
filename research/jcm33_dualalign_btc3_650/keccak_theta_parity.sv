module keccak_theta_parity(
    input  logic [1599:0] state_in,
    output logic [319:0]  c_out
);
    logic [63:0] A [0:24];
    logic [63:0] C [0:4];
    integer x, i;

    always_comb begin
        for (i=0; i<25; i=i+1)
            A[i] = state_in[i*64 +: 64];

        for (x=0; x<5; x=x+1)
            C[x] = A[x] ^ A[x+5] ^ A[x+10] ^ A[x+15] ^ A[x+20];

        for (x=0; x<5; x=x+1)
            c_out[x*64 +: 64] = C[x];
    end
endmodule
