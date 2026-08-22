set script_dir [file dirname [file normalize [info script]]]
set sim_dir [file normalize [file join $script_dir sim_engine]]

create_project -force sim_engine $sim_dir -part xcvu33p-fsvh2104-2-e

add_files [list \
    [file join $script_dir keccak_theta_parity.sv] \
    [file join $script_dir keccak_theta_apply_rhopi.sv] \
    [file join $script_dir keccak_chi.sv] \
    [file join $script_dir keccak_iota.sv] \
    [file join $script_dir keccak_f1600_ii1_pipeline.sv] \
    [file join $script_dir sha3t_ii1_pipeline.sv] \
    [file join $script_dir sha3t_ii1_miner_engine.sv] \
    [file join $script_dir tb_sha3t_ii1_miner_engine.sv] \
]

set_property file_type SystemVerilog [get_files *.sv]
set_property top tb_sha3t_ii1_miner_engine [get_filesets sim_1]
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
exit
