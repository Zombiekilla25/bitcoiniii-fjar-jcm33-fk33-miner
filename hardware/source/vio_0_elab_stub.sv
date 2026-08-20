module vio_0(
    input  logic         clk,
    input  logic [40:0]  probe_in0,
    input  logic [255:0] probe_in1,
    input  logic [31:0]  probe_in2,
    output logic [255:0] probe_out0,
    output logic [255:0] probe_out1,
    output logic [95:0]  probe_out2,
    output logic [255:0] probe_out3,
    output logic [9:0]   probe_out4
);
    always_comb begin
        probe_out0 = '0;
        probe_out1 = '0;
        probe_out2 = '0;
        probe_out3 = '0;
        probe_out4 = '0;
    end
endmodule
