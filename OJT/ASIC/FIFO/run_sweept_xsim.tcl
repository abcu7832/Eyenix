# run_sweep_xsim.tcl
set here [file dirname [info script]]
cd $here

set Ms {2 3 4 5 6 7 8 9 10 11 12 13 14 15 16}
#set Ns {2 3 4 5 6 7 8 9 10 11 12 13 14 15 16}

# include paths
set INC_TB  "../asic_lab-main/LAB_0/SIM/TB"
set INC_LIB "../asic_lab-main/LAB_0/LIB"

# source files
set TB    "../asic_lab-main/LAB_0/SIM/TB/tb_main.sv"
set DUT   "./asic_lab0.srcs/sources_1/new/MtoN_async_fifo.sv"
set ASYNC "../asic_lab-main/LAB_0/RTL/async_fifo.v"

foreach M $Ms {
    puts "==============================="
    puts " RUN : M_WRITERS = $M"
    puts "==============================="

    # compile
    exec xvlog -sv \
        -i $INC_TB \
        -i $INC_LIB \
        $TB $DUT $ASYNC

    # elaborate (⭐ 핵심: -generic)
    exec xelab -debug typical \
        -top tb_main \
        -snapshot sim_M${M} \
        -generic M_WRITERS=$M

    # run
    exec xsim sim_M${M} -runall -log log_M${M}.txt
}

#foreach N $Ns {
#    puts "==============================="
#    puts " RUN : N_READERS = $N"
#    puts "==============================="
#
#    # compile
#    exec xvlog -sv \
#        -i $INC_TB \
#        -i $INC_LIB \
#        $TB $DUT $ASYNC
#
#    # elaborate (⭐ 핵심: -generic)
#    exec xelab -debug typical \
#        -top tb_main \
#        -snapshot sim_N${N} \
#        -generic N_READERS=$N
#
#    # run
#    exec xsim sim_N${N} -runall -log log_N${N}.txt
#}
puts "==== ALL SWEEP DONE ===="

