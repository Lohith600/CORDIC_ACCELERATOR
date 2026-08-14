set design [lindex $argv 0]
set xpr    [lindex $argv 1]
set outdir [lindex $argv 2]

open_project $xpr
open_run impl_1

report_utilization -file [file join $outdir "${design}_impl_utilization.rpt"]
report_timing_summary -file [file join $outdir "${design}_impl_timing_summary.rpt"] -max_paths 10

puts "DONE_$design"
