set xpr [lindex $argv 0]

open_project $xpr
launch_runs impl_1 -to_step route_design -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    puts "IMPL_FAILED"
    exit 1
}
puts "IMPL_OK"
