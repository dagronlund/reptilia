//!import std/std_pkg.sv
//!import riscv/riscv_pkg.sv
//!import riscv/riscv32_pkg.sv
//!import gecko/gecko_pkg.sv
//!import mem/mem_combinational.sv

// Stores the values of the register file in combinational memory (read addr to
// read data is 0 cycles), along with their respective statuses. The register
// status is stored in two memories, one each for the front and rear status. The
// front status is updated when a register is planned to be written to, and the
// rear status is updated when a register is done being written to. By comparing
// the difference between the front and rear status the validity of the register
// can be determined.
module gecko_decode_regfile
    import std_pkg::*;
    import riscv_pkg::*;
    import riscv32_pkg::*;
    import gecko_pkg::*;
#(
    parameter std_clock_info_t CLOCK_INFO = 'b0,
    parameter std_technology_t TECHNOLOGY = STD_TECHNOLOGY_FPGA_XILINX
)(
    input wire clk, 
    input wire rst,

    input  riscv32_reg_addr_t  rs1_addr,
    output riscv32_reg_value_t rs1_value,
    output gecko_reg_status_t  rs1_status,
    output gecko_reg_status_t  rs1_status_front_last,

    input  riscv32_reg_addr_t  rs2_addr,
    output riscv32_reg_value_t rs2_value,
    output gecko_reg_status_t  rs2_status,
    output gecko_reg_status_t  rs2_status_front_last,

    input  wire                rd_read_enable,
    input  riscv32_reg_addr_t  rd_read_addr,
    output gecko_reg_status_t  rd_read_status,
    output gecko_reg_status_t  rd_read_status_front,

    input  wire                rd_write_enable,
    input  wire                rd_write_value_enable,
    input  riscv32_reg_addr_t  rd_write_addr,
    input  riscv32_reg_value_t rd_write_value,

    output logic reset_done
);

    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH($bits(riscv32_reg_value_t)),
        .ADDR_WIDTH($bits(riscv32_reg_addr_t)),
        .READ_PORTS(2),
        .AUTO_RESET(1)
    ) register_file_inst (
        .clk, .rst,

        // Always write to all bits in register
        .write_enable(rd_write_value_enable),
        .write_addr(rd_write_addr),
        .write_data_in(rd_write_value),
        .write_data_out(),

        .read_addr({rs1_addr, rs2_addr}),
        .read_data_out({rs1_value, rs2_value}),

        .reset_done
    );

    gecko_reg_status_t rd_status_front, rs1_status_front, rs2_status_front;

    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH($bits(gecko_reg_status_t)),
        .ADDR_WIDTH($bits(riscv32_reg_addr_t)),
        .READ_PORTS(2),
        .AUTO_RESET(1)
    ) register_status_front_inst (
        .clk, .rst,

        .write_enable(rd_read_enable),
        .write_addr(rd_read_addr),
        // Simply increment the status when written to
        .write_data_in(rd_status_front + 'b1),
        .write_data_out(rd_status_front),

        .read_addr({rs1_addr, rs2_addr}),
        .read_data_out({rs1_status_front, rs2_status_front}),

        .reset_done()
    );

    gecko_reg_status_t rd_write_status;
    gecko_reg_status_t rd_status_rear, rs1_status_rear, rs2_status_rear;

    mem_combinational #(
        .CLOCK_INFO(CLOCK_INFO),
        .TECHNOLOGY(TECHNOLOGY),
        .DATA_WIDTH($bits(gecko_reg_status_t)),
        .ADDR_WIDTH($bits(riscv32_reg_addr_t)),
        .READ_PORTS(3),
        .AUTO_RESET(1)
    ) register_status_rear_inst (
        .clk, .rst,

        .write_enable(rd_write_enable),
        .write_addr(rd_write_addr),
        // Simply increment the status when written to
        .write_data_in(rd_write_status + 'b1),
        .write_data_out(rd_write_status),

        .read_addr({rd_read_addr, rs1_addr, rs2_addr}),
        .read_data_out({rd_status_rear, rs1_status_rear, rs2_status_rear}),

        .reset_done()
    );

    always_comb rs1_status     = rs1_status_front - rs1_status_rear;
    always_comb rs2_status     = rs2_status_front - rs2_status_rear;
    always_comb rd_read_status = rd_status_front  - rd_status_rear;

    // Use to compare forwarded results to
    always_comb rs1_status_front_last = rs1_status_front - 'b1;
    always_comb rs2_status_front_last = rs2_status_front - 'b1;
    always_comb rd_read_status_front  = rd_status_front;

endmodule
