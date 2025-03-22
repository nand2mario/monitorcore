if {$argc == 0} {
    puts "Usage: $argv0 <device>"
    puts "          device: nano20k, primer25k, mega60k, mega138k, mega138k_31002, console60k"
    exit 1
}

set dev [lindex $argv 0]

if {$dev eq "nano20k"} {
    set_device GW2AR-LV18QN88C8/I7 -device_version C
    add_file -type verilog "src/nano20k/config.v"
    add_file -type verilog "src/nano20k/gowin_pll_hdmi.v"
    add_file -type cst "src/nano20k/monitor.cst"
} elseif {$dev eq "primer25k"} {
    set_device GW5A-LV25MG121NC1/I0 -device_version A
    add_file -type verilog "src/primer25k/config.v"
    add_file -type verilog "src/console60k/pll_27.v"
    add_file -type verilog "src/console60k/pll_74.v"
    add_file -type cst "src/primer25k/monitor.cst"
    set_option -use_ready_as_gpio 1
    set_option -use_done_as_gpio 1
} elseif {$dev eq "mega60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    add_file -type verilog "src/mega60k/config.v"
    add_file -type verilog "src/console60k/pll_27.v"
    add_file -type verilog "src/console60k/pll_74.v"
    add_file -type cst "src/mega60k/monitor.cst"
} elseif {$dev eq "mega138k"} {
    set_device GW5AST-LV138PG484AC1/I0 -device_version B
    add_file -type verilog "src/mega60k/config.v"
    add_file -type verilog "src/mega138k/pll_27.v"
    add_file -type verilog "src/mega138k/pll_74.v"
    add_file -type cst "src/mega60k/monitor.cst"
} elseif {$dev eq "mega138k_31002"} {
    set_device GW5AST-LV138PG484AC1/I0 -device_version B
    add_file -type verilog "src/mega60k/config.v"
    add_file -type verilog "src/mega138k/pll_27.v"
    add_file -type verilog "src/mega138k/pll_74.v"
    add_file -type cst "src/mega138k/monitor_31002.cst"
} elseif {$dev eq "console60k"} {
    set_device GW5AT-LV60PG484AC1/I0 -device_version B
    add_file -type verilog "src/console60k/config.v"
    add_file -type verilog "src/console60k/pll_27.v"
    add_file -type verilog "src/console60k/pll_74.v"
    add_file -type verilog "src/console60k/pll_12.v"
    add_file -type verilog "src/usb_hid_host.v"
    add_file -type cst "src/console60k/monitor.cst"
} else {
    error "Unknown device $dev"
}
set_option -output_base_name monitor_${dev}

add_file -type verilog "src/controller_ds2.sv"
add_file -type verilog "src/controller_snes.v"
add_file -type verilog "src/dualshock_controller.v"
add_file -type verilog "src/hdmi/audio_clock_regeneration_packet.sv"
add_file -type verilog "src/hdmi/audio_info_frame.sv"
add_file -type verilog "src/hdmi/audio_sample_packet.sv"
add_file -type verilog "src/hdmi/auxiliary_video_information_info_frame.sv"
add_file -type verilog "src/hdmi/hdmi.sv"
add_file -type verilog "src/hdmi/packet_assembler.sv"
add_file -type verilog "src/hdmi/packet_picker.sv"
add_file -type verilog "src/hdmi/serializer.sv"
add_file -type verilog "src/hdmi/source_product_description_info_frame.sv"
add_file -type verilog "src/hdmi/tmds_channel.sv"
add_file -type verilog "src/iosys/gowin_dpb_menu.v"
add_file -type verilog "src/iosys/iosys_bl616.v"
add_file -type verilog "src/iosys/textdisp.v"
add_file -type verilog "src/iosys/uart_fixed.v"
add_file -type verilog "src/monitor2hdmi.v"
add_file -type verilog "src/monitor_top.v"
add_file -type gao -disable "src/monitor_console60k.rao"
set_option -synthesis_tool gowinsynthesis
set_option -top_module monitor_top
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -use_sspi_as_gpio 1
set_option -use_mspi_as_gpio 1
set_option -use_cpu_as_gpio 1

run all
