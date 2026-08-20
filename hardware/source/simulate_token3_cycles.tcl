create_project -force sim_token3_cycles ./sim_token3_cycles
add_files [list \
    ./keccak_theta_parity.sv \
    ./keccak_theta_apply_rhopi.sv \
    ./keccak_chi.sv \
    ./keccak_iota.sv \
    ./sha3t_token4_core.sv \
]
add_files -fileset sim_1 ./tb_token3_cycles.sv
set_property top tb_token4 [get_filesets sim_1]
launch_simulation
run all
quit
