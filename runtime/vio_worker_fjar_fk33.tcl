set_param xicom.use_bitstream_version_check false

if {[llength $argv] < 1} {
    error "Usage: -tclargs <FK_SERIAL> ?RUN_DIR?"
}

set serial [lindex $argv 0]

if {[llength $argv] >= 2} {
    set run_dir [file normalize [lindex $argv 1]]
} else {
    set run_dir [pwd]
}

file mkdir $run_dir

set script_dir [file dirname [file normalize [info script]]]
set release_dir [file dirname $script_dir]
set bit_file [file join \
    $release_dir hardware prebuilt fk33_fjar_80pipe_token3_350mhz.bit]
set ltx_file [file join \
    $release_dir hardware prebuilt fk33_fjar_80pipe_token3_350mhz.ltx]

puts [format {FJAR_WORKER_START serial=%s run_dir=%s} $serial $run_dir]

open_hw_manager
connect_hw_server

set targets [get_hw_targets *$serial*]
if {[llength $targets] != 1} {
    error "Expected exactly one FK target for serial $serial, found [llength $targets]"
}

set target [lindex $targets 0]
current_hw_target $target
open_hw_target

set dev [lindex [get_hw_devices xcvu33p*] 0]
if {$dev eq ""} {
    error "No XCVU33P found on target $serial"
}

current_hw_device $dev

set_property PROGRAM.FILE $bit_file $dev
set_property PROBES.FILE  $ltx_file $dev

puts [format {PROGRAMMING serial=%s bit=%s} $serial $bit_file]
program_hw_devices $dev
refresh_hw_device $dev
puts [format {PROGRAM_COMPLETE serial=%s} $serial]

set vios [get_hw_vios]
if {[llength $vios] != 1} {
    error "Expected exactly one VIO core on $serial, found [llength $vios]"
}
set vio [lindex $vios 0]

proc one_probe {name} {
    set p [get_hw_probes -quiet $name]
    if {[llength $p] != 1} {
        error "Expected exactly one probe named $name, found [llength $p]"
    }
    return [lindex $p 0]
}

set p0 [one_probe vio_header0]
set p1 [one_probe vio_header1]
set p2 [one_probe vio_header2]
set pt [one_probe vio_target]
set pc [one_probe vio_control]

set ps [one_probe vio_status_mailbox]
set pd [one_probe vio_digest_mailbox]
set pn [one_probe vio_live_nonce]

foreach p [list $p0 $p1 $p2 $pt $pc] {
    set_property OUTPUT_VALUE_RADIX HEX $p
}
foreach p [list $ps $pd $pn] {
    set_property INPUT_VALUE_RADIX HEX $p
}

set job_file    [file join $run_dir job.txt]
set share_file  [file join $run_dir candidate.txt]
set status_file [file join $run_dir vio_status.txt]

catch {file delete -force $share_file}
catch {file delete -force $status_file}

set job_toggle 0
set ack_toggle 0
set active_tag 0
set seen_share_keys [dict create]
set poll_count 0

proc write_control {pc vio job_toggle ack_toggle tag} {
    set ctl [expr {
        (($job_toggle & 1) << 9) |
        (($ack_toggle & 1) << 8) |
        ($tag & 255)
    }]
    set_property OUTPUT_VALUE [format "%03x" $ctl] $pc
    commit_hw_vio $vio
}

set_property OUTPUT_VALUE [string repeat 0 64] $p0
set_property OUTPUT_VALUE [string repeat 0 64] $p1
set_property OUTPUT_VALUE [string repeat 0 24] $p2
set_property OUTPUT_VALUE [string repeat 0 64] $pt
write_control $pc $vio $job_toggle $ack_toggle $active_tag

puts [format {FJAR_WORKER_READY serial=%s run_dir=%s} $serial $run_dir]
flush stdout

while {1} {
    if {[file exists $job_file]} {
        if {[catch {
            set fp [open $job_file r]

            set tag_s    [string trim [gets $fp]]
            set p0_s     [string trim [gets $fp]]
            set p1_s     [string trim [gets $fp]]
            set p2_s     [string trim [gets $fp]]
            set target_s [string trim [gets $fp]]

            close $fp

            scan $tag_s %x active_tag
            set active_tag [expr {$active_tag & 255}]

            set_property OUTPUT_VALUE $p0_s $p0
            set_property OUTPUT_VALUE $p1_s $p1
            set_property OUTPUT_VALUE $p2_s $p2
            set_property OUTPUT_VALUE $target_s $pt

            set job_toggle [expr {!$job_toggle}]
            write_control $pc $vio $job_toggle $ack_toggle $active_tag

            file delete -force $job_file

            puts [format \
                {JOB serial=%s tag=%02x target=%s} \
                $serial $active_tag $target_s]
            flush stdout

        } err]} {
            puts stderr [format \
                {JOB_ERROR serial=%s error=%s} \
                $serial $err]
            catch {close $fp}
            catch {file delete -force $job_file}
            flush stderr
        }
    }

    if {[catch {
        refresh_hw_vio $vio
        incr poll_count

        set status_hex     [get_property INPUT_VALUE $ps]
        set digest_hex     [get_property INPUT_VALUE $pd]
        set batch_gray_hex [get_property INPUT_VALUE $pn]

        scan $status_hex %x status_int

        set pending [expr {($status_int >> 40) & 1}]
        set tag     [expr {($status_int >> 32) & 255}]
        set nonce   [expr {$status_int & 0xffffffff}]

        scan $batch_gray_hex %x batch_gray

        set batch_bin $batch_gray
        set batch_bin [expr {$batch_bin ^ ($batch_bin >> 1)}]
        set batch_bin [expr {$batch_bin ^ ($batch_bin >> 2)}]
        set batch_bin [expr {$batch_bin ^ ($batch_bin >> 4)}]
        set batch_bin [expr {$batch_bin ^ ($batch_bin >> 8)}]
        set batch_bin [expr {$batch_bin ^ ($batch_bin >> 16)}]

        set live_nonce_int [expr {($batch_bin * 256) & 0xffffffff}]
        set live_nonce [format "%08x" $live_nonce_int]

        # Remote hw_server refreshes can be much slower than the nominal
        # 10 ms loop. Publish every five successful polls so the fleet
        # monitor normally receives multiple samples within one pool job.
        if {$poll_count % 5 == 0} {
            set sf [open $status_file w]
            puts $sf [format "%02x:%s:%d" \
                $active_tag $live_nonce $pending]
            close $sf
        }

        if {$pending} {
            set key [format "%02x:%08x:%s" \
                $tag $nonce $digest_hex]

            if {![dict exists $seen_share_keys $key]} {
                dict set seen_share_keys $key 1

                # Keep memory bounded during long mining runs.
                if {[dict size $seen_share_keys] > 4096} {
                    set seen_share_keys [dict create $key 1]
                }

                set tmp "${share_file}.tmp"
                set cf [open $tmp w]
                puts $cf $key
                close $cf
                file rename -force $tmp $share_file

                puts [format {REAL_SHARE serial=%s %s} \
                    $serial $key]
                flush stdout

                set ack_toggle [expr {!$ack_toggle}]
                write_control \
                    $pc $vio \
                    $job_toggle $ack_toggle $active_tag
            }
        }

    } poll_err]} {
        puts stderr [format \
            {POLL_ERROR serial=%s error=%s} \
            $serial $poll_err]
        flush stderr
        after 500
    }

    after 10
}
