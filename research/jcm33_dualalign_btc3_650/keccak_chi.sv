module keccak_chi(
    input  logic [1599:0] b_in,
    output logic [1599:0] chi_out
);
    logic [63:0] B [0:24];
    logic [63:0] O [0:24];
    integer x, y, i;

    always_comb begin
        for (i=0; i<25; i=i+1)
            B[i] = b_in[i*64 +: 64];

        for (y=0; y<5; y=y+1)
            for (x=0; x<5; x=x+1)
                O[x+5*y] =
                    B[x+5*y] ^
                    ((~B[((x+1)%5)+5*y]) &
                       B[((x+2)%5)+5*y]);

        for (i=0; i<25; i=i+1)
            chi_out[i*64 +: 64] = O[i];
    end
endmodule
