# ==============================================================================
# create_vip_project.tcl
# Vivado シミュレーションプロジェクト自動生成スクリプト (AXI VIP 使用)
#
# 使い方:
#   Vivado Tcl Console:
#     source <path_to_repo>/sim/create_vip_project.tcl
#
#   コマンドライン:
#     vivado -mode batch -source sim/create_vip_project.tcl
#
# 生成されるもの:
#   ./vivado_vip_sim/                    - Vivadoプロジェクトディレクトリ
#   ./vivado_vip_sim/ip/axi_vip_mst_0/  - AXI VIP IP (Master モード)
#   xsim シミュレーション設定
# ==============================================================================

# ==============================================================================
# 設定変数
# ==============================================================================
set project_name  "ltc2668_vip_sim"
set project_dir   "[file normalize [file dirname [info script]]]/../vivado_vip_sim"
set repo_root     "[file normalize [file dirname [info script]]]/.."
set part          "xc7z020clg400-1"    ;# Zynq-7020 (任意のデバイスに変更可)

# ==============================================================================
# プロジェクト作成
# ==============================================================================
puts "INFO: Creating project: $project_name"
create_project $project_name $project_dir -part $part -force

set_property simulator_language Mixed [current_project]
set_property target_simulator XSim   [current_project]

# ==============================================================================
# RTL ソース追加 (DUT)
# ==============================================================================
puts "INFO: Adding DUT source files"
add_files [file normalize "$repo_root/hdl/ltc2668_axi.sv"]
set_property file_type SystemVerilog [get_files ltc2668_axi.sv]

# ==============================================================================
# AXI VIP IP 生成 (Master モード, AXI4-Lite, 32-bit/8-bit addr)
# ==============================================================================
puts "INFO: Generating AXI VIP IP (Master, AXI4LITE, 32/8)"

set ip_dir "$project_dir/ip/axi_vip_mst_0"
file mkdir $ip_dir

create_ip \
    -name         axi_vip \
    -vendor       xilinx.com \
    -library      ip \
    -version      1.1 \
    -module_name  axi_vip_mst_0 \
    -dir          $ip_dir

set_property -dict [list \
    CONFIG.INTERFACE_MODE {MASTER}   \
    CONFIG.PROTOCOL       {AXI4LITE} \
    CONFIG.DATA_WIDTH     {32}       \
    CONFIG.ADDR_WIDTH     {8}        \
    CONFIG.HAS_BURST      {0}        \
    CONFIG.HAS_LOCK       {0}        \
    CONFIG.HAS_CACHE      {0}        \
    CONFIG.HAS_QOS        {0}        \
    CONFIG.HAS_REGION     {0}        \
] [get_ips axi_vip_mst_0]

generate_target {instantiation_template simulation} [get_ips axi_vip_mst_0]
generate_target all [get_ips axi_vip_mst_0]

export_ip_user_files \
    -of_objects [get_ips axi_vip_mst_0] \
    -no_script -reset -force -quiet

# ==============================================================================
# テストベンチ追加 (sim fileset)
# ==============================================================================
puts "INFO: Adding testbench to sim_1 fileset"

add_files \
    -fileset sim_1 \
    [file normalize "$repo_root/sim/ltc2668_axi_vip_tb.sv"]

set_property file_type SystemVerilog \
    [get_files -of_objects [get_filesets sim_1] ltc2668_axi_vip_tb.sv]

# Simulation トップモジュール設定
set_property top            ltc2668_axi_vip_tb [get_filesets sim_1]
set_property top_lib        xil_defaultlib     [get_filesets sim_1]

# xsim シミュレーション時間設定
set_property -name {xsim.simulate.runtime}       -value {10ms}  -objects [get_filesets sim_1]
set_property -name {xsim.simulate.log_all_signals} -value {true} -objects [get_filesets sim_1]

# ==============================================================================
# IP Repo パス (必要に応じてカスタム IP を追加)
# ==============================================================================
set_property ip_repo_paths [file normalize "$repo_root"] [current_project]
update_ip_catalog -rebuild

# ==============================================================================
# シミュレーション実行
# ==============================================================================
puts "INFO: Launching simulation"

launch_simulation

# シミュレーション開始
run all

puts "INFO: Simulation complete"
puts "INFO: Check the Tcl console for PASS/FAIL results"

# ==============================================================================
# 完了メッセージ
# ==============================================================================
puts ""
puts "============================================================"
puts " Project created: $project_dir"
puts " - DUT source   : hdl/ltc2668_axi.sv"
puts " - VIP instance : axi_vip_mst_0 (Master, AXI4LITE, 32/8)"
puts " - Testbench    : sim/ltc2668_axi_vip_tb.sv"
puts "============================================================"
puts " To re-run simulation from Vivado Tcl Console:"
puts "   relaunch_sim"
puts "   run all"
puts "============================================================"
