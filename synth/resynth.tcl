set xpr [lindex $argv 0]

open_project $xpr
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "SYNTH_FAILED"
    exit 1
}
puts "SYNTH_OK"
