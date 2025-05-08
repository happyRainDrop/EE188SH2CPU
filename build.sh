#!/bin/bash
set -e
ghdl -a -fsynopsys --std=08 reg.vhd
ghdl -a -fsynopsys --std=08 alu.vhd
ghdl -a -fsynopsys --std=08 mau.vhd
ghdl -a -fsynopsys --std=08 memory.vhd
ghdl -a -fsynopsys --std=08 SH2reg.vhd
ghdl -a -fsynopsys --std=08 SH2alu.vhd
ghdl -a -fsynopsys --std=08 SH2DMAU.vhd
ghdl -a -fsynopsys --std=08 SH2PMAU.vhd
ghdl -a -fsynopsys --std=08 CPUtoplevel.vhd
ghdl -a -fsynopsys --std=08 CPU_Testbench.vhd
