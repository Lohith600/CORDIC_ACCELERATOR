set design  [lindex $argv 0]
set xpr     [lindex $argv 1]
set outdir  [lindex $argv 2]

open_project $xpr
open_run synth_1

report_utilization -file [file join $outdir "${design}_utilization.rpt"]
report_timing_summary -file [file join $outdir "${design}_timing_summary.rpt"] -max_paths 10
report_timing -delay_type max -sort_by slack -max_paths 10 -path_type full -file [file join $outdir "${design}_worst_paths.rpt"]

puts "DONE_$design"
