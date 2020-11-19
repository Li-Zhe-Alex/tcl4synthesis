#=====================================================
# Project     : Design Compiler
# File Name   : top.tcl
# Author      : Li_Zhe
# E-mail      : nbaislizhe@gmail.com
# Version     : 
# V1.0        Initial version  2020.10.24
#=====================================================

#=====================================================
# Step 1: Read & eleaborate the RTL file list & check
#=====================================================
set TOP_MODULE top
analyze -format verilog [List fsm_moore.v top.v counter.v]
elaborate      $TOP_MODULE -architecture verilog
current_design $TOP_MODULE

if {[link] == 0} {
	echo "Link with error!";
	exit;
}     #防止忘记设置link library,或者set错。其实不需要，但是为了强化

if {[check_design] == 0} {
	echo "Check design with error!";
	exit;
} 

#=====================================================
# Step 2: reset the design first
#=====================================================
reset_design   #把之前的约束扔掉，重来

#=====================================================
# Step 3: Write the unmapped ddc file
#=====================================================
uniquify
set uniquify_naming_style "%s_%d"
write -f ddc -hierarchy -output ${UNMAPPED_PATH}/{TOP_MODULE}.ddc
#这一步可以将rtl转化的GTECH(unmapped)文件保存，下一次想继续执行，输入 read ddc ${UNMAPPED_PATH}/{TOP_MODULE}.ddc来执行 

#=====================================================
# Step 4: Define clock
#=====================================================
set  CLK_NAME          clk_i
set  CLK_PERIOD        10
set  CLK_SKEW          [expr  $CLK_PERIOD*0.05]
set  CLK_TRAN          [expr  $CLK_PERIOD*0.01]
set  CLK_SRC_LATENCY   [expr  $CLK_PERIOD*0.1]
set  CLK_LATENCY       [expr  $CLK_PERIOD*0.1]

create_clock   -period   $CLK_PERIOD      [get_ports  $CLK_NAME]
set_ideal_network      [get_ports  $CLK_NAME]  #这两句是废话，不过强化clk是ideal_network,
set_dont_touch_network [get_ports  $CLK_NAME]  #告诉DC不对clk做优化
set_drive    0         [get_ports  $CLK_NAME]  #设置驱动，0代表无穷大
set_clock_uncertainty  -setup   $CLK_SKEW        [get_ports  $CLK_NAME]  #偏移
set_clock_transition   -max     $CLK_TRAN        [get_ports  $CLK_NAME]  #斜率反转，非直角翻转
set_clock_latency -source -max  $CLK_SRC_LATENCY [get_ports  $CLK_NAME]  #PCB版上晶振到芯片引脚的延迟
set_clock_latency -max          $CLK_LATENCY     [get_ports  $CLK_NAME]  #芯片引脚到内部触发器的延迟


#=====================================================
# Step 4: Define reset
#=====================================================
set  RST_NAME          rst_l_i
set_ideal_network      [get_ports $RST_NAME]
set_dont_touch_network [get_ports $RST_NAME]
set_drive    0         [get_ports $RST_NAME]

#=====================================================
# Step 5: Set input delay (Using timing budget)
# Assume a weak cell to drive the inputs pins
#=====================================================
set   LIB_NAME          scx_csm_18ic_ss_lp62v_125c
set   WIRE_LOAD_MODEL   csm18_wl10
set   DRIVE_CELL        INVX1
set   DRIVE_PIN         Y
set   OPERA_CONDITION   ss_lp62v_125c
set   ALL_IN_EXCEPT_CLK [remove_from_collection [all_inputs] [get_ports "$CLK_NAME"]]
set_input_delay         $INPUT_DELAY     -clock  $CLK_NAME   $ALL_IN_EXCEPT_CLK #相对CLK_NAME对哪些端口设置延迟
#set_input_delay    -min   0    -clock $CLK_NAME   $ALL_IN_EXCEPT_CLK
set_driving_cell    -lib_cell ${DRIVE_CELL}  -pin ${DRIVE_PIN} $ALL_IN_EXCEPT_CLK 
#给某些端口加库里某个cell的某个pin作为负载


#=====================================================
# Step 6: Set output delay
#=====================================================
set    OUTPUT_DELAY     [expr  $CLK_PERIOD*0.6]
set    MAX_LOAD         [expr  [load_of $LIB_NAME/INVX8/A] * 10]
set_output_delay        $OUTPUT_DELAY    -clock   $CLK_NAME [all_outputs]
set_load                [expr  $MAX_LOAD * 3]  [all_outputs]
set_isilate_ports       -type buffer (or inv)           [all_outputs]
#将外部端口用buffer或者反相器和内部隔离开来，如果不加，当电路出现反馈，输出端口会影响反馈结果
#=====================================================
# Step 7: Set max delay for comb logic
#=====================================================
#set_input_delay        [expr $CLK_PERIOD * 0.1] -clock $CLK_NAME -add_delay [get_ports a_i]
#set_output_delay       [expr $CLK_PERIOD * 0.1] -clock $CLK_NAME -add_delay [get_ports y_o]

#=====================================================
# Step 8: Set operating condition & wire load model
#=====================================================
set_operating_conditions    -max   $OPERA_CONDITION \
							-max_library  $LIB_NAME  #设置工作条件
set auto_wire_load_selection  false				#告诉DC自动线负载模型关掉
set_wire_load_mode   top						#
set_wire_load_model         -name  $WIRE_LOAD_MODEL \
							-library      $LIB_NAME  #设置线负载模型
							
#=====================================================
# Step 9: Set area constraint (Let's DC try its best)
#=====================================================
set_max_area   0  #期望面积最小为0


#=====================================================
# Step 10: Set DRC constraint
#=====================================================
#set  MAX_CAPACITANCE  [expr [load_of $LIB_NAME/NAND4X2/Y] * 5]
#set_max_capacitance   $MAX_CAPACITANCE   $ALL_IN_EXCEPT_CLK


#=====================================================
# Step 11: Set DRC constraint
# Avoid getting stack on one path （遇到violation才使用这个部分，如果加了还是违例，就得修改代码了）
#=====================================================
group_path   -name   $CLK_NAME  -weight \
								-critical_range   [expr $CLK_PERIOD * 0.1]
#指定一个group名字，指定一个权重（路径差，需要尽最大优化）\指定一个范围，对这个范围内的路径进行优化，一般不超过周期%10。通常分为下面几个组：输入，输出，之间的路径							
group_path   -name   INPUTS     -from [all_inputs] \
								-critical_range   [expr $CLK_PERIOD * 0.1]
group_path   -name   OUTPUTS    -to [all_inputs] \
								-critical_range   [expr $CLK_PERIOD * 0.1]
group_path   -name   COMB       -from [all_inputs] \
								-to [all_outputs] \
								-critical_range   [expr $CLK_PERIOD * 0.1]	
report_path_group								

#=====================================================
# Step 12: Elimate the multipile-port inter-connect & define name style
#=====================================================
set_app_var   verilogout_no_tri                true    #verilog不要用tri类型，而用wire。如果用了DC会帮助转换
set_app_var   verilogout_show_unconnected_pins true    #显示没有连的端口，为后端方便
set_app_var   bus_naming_style                 {%s[%d]} #设置总线命名规则
simplify_constants  -boundary_optimization #边界优化
set_fix_multiple_port_nets  -all  -buffer_constants  #端口连端口加buffer，避免端口连端口，或者端口接0

#=====================================================
# Step 13: Timing exception define
#=====================================================
# set_false_path  -from  [get_clocks clk1_i] -to [get_cloks clk2_i]
# set ALL_CLOCKS [all_clocks]
#foreach_in_collection CUR_CLK SALL_CLOCKS {
#   set OTHER_CLKS [remove_from_collection [all_clocks] $CUR_CLK]
#	set_false_path -from $CUR_CLK $OTHER_CLKS
#}

set false_path  -from [get_clocks $CLK1_NAME]  -to [get_clocks $CLK2_NAME]
set false_path  -from [get_clocks $CLK2_NAME]  -to [get_clocks $CLK1_NAME]
#需要在第四五步define clock定义两个时钟和复位，加上述两个不相关指令，告诉DC，不需要在这两条路径做优化
#set_disable_timing TOP/U1  -from a -to y_o
#set_case_analysis  0 [get_ports sel_i]

#set_multicycle_path  -setup 6 -from  FFA/CP  -through  ADD/out  -to FFB/D
#set_multicycle_path  -hold 5 -from  FFA/CP  -through  ADD/out  -to FFB/D
#set_multicycle_path  -setup 2 -to [get_pins q_lac*/D]
#set_multicycle_path  -hold 1 -to [get_pins q_lac*/D]

#=====================================================
# Step 14: compile flow
#=====================================================
#ungrouop -flatten -all :不以module形式显示
#lst-pass compile
compile -map_effort high -area_effort medium
#compile -map_effort medium -area_effort high -boundary_optimization
#
#simplify_constants -boundary_optimization
#set_fix_multiple_port_nets -all -buffer_constants
#
#compile -map_effort high -area_effort high -incremental_mapping -scan
# 2nd-pass compile
#compile -map_effort high -area_effort high -boundary_optimization -incremental_mapping
#compile_ultra -incr


#=====================================================
# Step 15: Write post-process files
#=====================================================
change_name -rules verilog -hierarchy  #避免综合后的门级网表一些名字加/。交给后端不认识
#remove_unconnected_ports [get_cells -hier *] .blast_buses
#write the mapped files
write -f ddc     -hierarchy  -output  $MAPPED_PATH/${TOP_MODULE}.ddc  #综合后图像界面，通过synopsis打开
write -f verilog -hierarchy  -output  $MAPPED_PATH/${TOP_MODULE}.v    #综合后门级网表
write_sdc -verilog 1.7                $MAPPED_PATH/${TOP_MODULE}.sdc  #综合时的约束指令
write_sdf -verilog 2.1                $MAPPED_PATH/${TOP_MODULE}.sdf  #时序信息，对后仿有用

#=====================================================
# Step 16: Generate report files
#=====================================================
# Get report file
#redirect  -tee -file ${REPORT_PATH}/check_design.txt   {check_design}
#redirect  -tee -file ${REPORT_PATH}/check_timing.txt   {check_timing}
#redirect  -tee -file ${REPORT_PATH}/report_constraint.txt   {report_constraint -all_violators}
#redirect  -tee -file ${REPORT_PATH}/check_setup.txt    {report_timing -delay_type max}
#redirect  -tee -file ${REPORT_PATH}/check_hold.txt     {report_timing -delay_type min}
#redirect  -tee -file ${REPORT_PATH}/report_area.txt    {report_area}
#重定向保存各种信息
#=====================================================
# Step 17: At the end
#=====================================================










#=====================================================
#需要一个top.tcl，如下
#redirect -tee -file ${WORK_PATH}/compile.log {source -echo -verbose this.tcl}
#先执行花括号里的指令，来执行top.tcl,然后调用this.tcl,然后把结果存放在compile.log中。

#=====================================================
# dcprocheck ../script/top.tcl :写完脚本可以使用指令来检查是否有语法错误
# source ../script/top.tcl :检查完毕后执行脚本




#=====================================================
#report_constraint  -all_violators :把所有违例报告
#report_timing :把路径报告出来
#report_timing -inputs_pins:把带端口名的路径报告出来
#report_timing -delay_type max :把最差的路径报告出来
#report_timing -max_paths 2:把不同分组的最差的2个路径报告出来
#report_timing -max_paths 2 -nworst 2 :把所有分组最差的2个路径报告出来
#report_timing -signficant_digits 4 :设置报告精度，这里到小数点后4位
#report_timing -loops :检查是否有组合逻辑环，否则会有latch


























