set script_path [ file dirname [ file normalize [ info script ] ] ]
set test_path [file join $script_path "../../riscv-tests/isa/rv32ui"]
set result_path [file join $script_path "../temp/vivado_builds/vivado_builds.sim/sim_1/behav/xsim"]
set result_file_path [file join $result_path "status.txt"]
set saved_path [pwd]
cd $script_path

set test_results_file [open [file join $result_path "test_results.txt"] w]

foreach test_file [glob -directory $test_path *.S] {
    exec python assembler.py $test_file
    relaunch_sim
    set result_file [open $result_file_path r]
    set result_string [gets $result_file]
    close $result_file
    set test_file_name [file tail $test_file]
    puts "$test_file_name $result_string"
    puts $test_results_file "$test_file_name $result_string"
    # break
}

close $test_results_file

cd $saved_path
