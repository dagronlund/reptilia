`timescale 1ns/1ps

`include "../lib/rv_util.svh"

module rv_i2c_controller (
    input logic clk, rst,
    
    rv_axi_addr_read_intf.in axi_ar,
    rv_axi_read_data_intf.out axi_r,
    
    rv_axi_addr_write_intf.in axi_aw,
    rv_axi_write_data_intf.in axi_w,
    rv_axi_write_resp_intf.out axi_b,

    rv_io_intf.out sda,
    rv_io_intf.out scl
);



endmodule

typedef enum logic {
    RV_I2C_WRITE = 1'b0,
    RV_I2C_READ = 1'b1
} rv_i2c_op;

typedef enum logic {
    RV_I2C_SUCCESS = 1'b0,
    RV_I2C_ACK_FAILURE = 1'b1
} rv_i2c_status;

// typedef enum logic {
//     RV_I2C_8 = 1'b0,
//     RV_I2C_16 = 1'b1
// } rv_i2c_size;

// typedef struct packed {
//     rv_i2c_size size;
//     logic [15:0] data;
// } rv_i2c_data;

typedef enum logic [1:0] {
    RV_I2C_ADDR8_DATA8,
    RV_I2C_ADDR8_DATA16,
    RV_I2C_ADDR16_DATA8,
    RV_I2C_ADDR16_DATA16
} rv_i2c_format;

typedef struct packed {
    rv_i2c_op op;
    rv_i2c_format format;
    logic [6:0] device;
    logic [15:0] addr, data;
} rv_i2c_command;

typedef struct packed {
    rv_i2c_status status;
    logic [15:0] data;
} rv_i2c_result;

`BUILD_STREAM_INTF(rv_i2c_command)
`BUILD_STREAM_INTF(rv_i2c_result)

module rv_i2c_phy_tx #(
    // parameter [11:0] DEFAULT_CYCLES = 250, // (100 MHz / 400 kHz)
    // parameter [10:0] DEFAULT_DELAY = 0
)(
    input logic clk, rst,

    rv_i2c_command_stream_intf.in command_stream,
    rv_i2c_result_stream_intf.in result_stream,

    input logic [9:0] cycles,
    input logic [10:0] delay,

    rv_io_intf.out sda,
    rv_io_intf.out scl  
);

    // // Allows speed to updated, divides each clock cycle into four quadrants
    // logic [9:0] cycle_limit, cycle_delay;

    // always_ff @(posedge clk) begin
    //     if(rst) begin
    //         cycle_limit <= DEFAULT_CYCLES[11:2];
    //         update_delay <= DEFAULT_DELAY;
    //     end else if (update) begin
    //         cycle_limit <= update_cycles[11:2];
    //         cycle_delay <= update_delay;
    //     end
    // end

    /*
    () Indicates the state can repeat for MSB and LSB

    Write:
    IDLE -> START -> DEVICE_WRITE -> (WRITE_ADDR) -> (WRITE_DATA) -> STOP
    
    Read:
    IDLE -> START -> DEVICE_WRITE -> (WRITE_ADDR) -> REPEATED_START -> DEVICE_READ -> (READ_DATA) -> STOP 
    */

    typedef enum logic [3:0] {
        I2C_IDLE,
        I2C_START, I2C_REPEATED_START, I2C_STOP,
        I2C_DEVICE_WRITE, I2C_DEVICE_READ,
        I2C_WRITE_ADDR_MSB, I2C_WRITE_ADDR_LSB, 
        I2C_WRITE_DATA_MSB, I2C_WRITE_DATA_LSB, 
        I2C_READ_DATA_MSB, I2C_READ_DATA_LSB
    } i2c_state;

    logic cycle_enable, cycle_clear, cycle_done;
    logic [9:0] current_cycle;
    rv_counter #(.WIDTH(10)) cycle_counter_inst (
        .clk, .rst,
        .enable(cycle_enable), .clear(cycle_clear),
        .value(current_cycle),
        .max(cycles), .complete(cycle_done)
    );

    logic quad_enable, quad_clear, quad_done;
    logic [1:0] current_quad;
    rv_counter #(.WIDTH(2)) quad_counter_inst (
        .clk, .rst,
        .enable(quad_enable), .clear(quad_clear),
        .value(current_quad),
        .max(2'b11), .complete(quad_done)
    );

    // 0 - 7 are transmitted bits and 8 is ack/nack
    logic bit_enable, bit_clear, bit_done;
    logic [3:0] current_bit;
    rv_counter #(.WIDTH(4)) bit_counter_inst (
        .clk, .rst,
        .enable(bit_enable), .clear(bit_clear),
        .value(current_bit),
        .max(4'd8), .complete(bit_done)
    );

    // Shifter register handles sda
    logic sda_present, sda_past;
    logic sda_shift_enable, sda_load_enable;
    logic [8:0] sda_load_value;
    rv_shift_register #(
        .WIDTH(9)
    ) sda_shift_register_inst (
        .clk, .rst,

        .enable(sda_shift_enable),
        .load_enable(sda_load_enable),
        .load_value(sda_load_value),

        .shift_out(sda_past),
        .shift_peek(sda_present)
    );

    i2c_state cs, ns;
    logic current_scl, next_scl;

    always_ff @ (posedge clk) begin
        if (rst) begin
            cs <= I2C_IDLE;
            current_scl <= 1'b1;
        end else begin
            cs <= ns;
            current_scl <= next_scl;
        end
    end

    // I2C is an open drain driver and when T is low, the output is enabled
    logic scl_out, sda_out, scl_in, sda_in;
    assign {scl.o, sda.o} = 2'b00;
    assign {scl.t, sda.t} = {current_scl, sda_out};
    assign {scl_in, sda_in} = {scl.i, sda.i};

    function logic [9:0] calculate_sda_sequence(
            input i2c_state state, input rv_i2c_command command
    );
        if (state == I2C_IDLE || state == I2C_START || state == I2C_REPEATED_START) begin
            return {10{1'b1}};
        end else if (state == I2C_STOP) begin
            if (command.op == RV_I2C_READ) begin
                return {1'b0, {9{1'b1}}}; // Output held to zero for nack before stop
            end else begin
                return {10{1'b1}};
            end
        // All are preceeded by a start and ends with an ack (slave)
        end else if (state == I2C_DEVICE_WRITE || state == I2C_DEVICE_READ) begin
            return {1'b0, command.device, command.op, 1'b1};
        end else if (state == I2C_WRITE_ADDR_MSB) begin
            return {1'b0, command.addr[15:8], 1'b1};
        end else if (state == I2C_WRITE_ADDR_LSB) begin
            return {1'b0, command.addr[7:0], 1'b1};
        end else if (state == I2C_WRITE_DATA_MSB) begin
            return {1'b0, command.data[15:8], 1'b1};
        end else if (state == I2C_WRITE_DATA_LSB) begin
            return {1'b0, command.data[7:0], 1'b1};
        end else if (state == I2C_READ_DATA_MSB || state == I2C_READ_DATA_LSB) begin
            return {1'b0, {8{1'b1}}, 1'b0};
        end else begin
            return {10{1'b1}};
        end
    endfunction

    function logic calculate_sda(
            input i2c_state state, input logic [1:0] quad,
            input logic sda_past, sda_present
    );
        case (state)
        I2C_IDLE: return 1'b1;
        I2C_START:
            case (quad)
            2'b11: return 1'b0;
            default: return 1'b1;
            endcase
        I2C_REPEATED_START:
            case (quad)
            2'b11: return 1'b0;
            default: return 1'b1;
            endcase
        I2C_STOP:
            case (quad)
            2'b00: return sda_past;
            2'b01: return 1'b0;
            2'b10: return 1'b0;
            2'b11: return 1'b1;
            endcase
        default:
            case (quad)
            2'b00: return sda_past;
            default: return sda_present;
            endcase
        endcase
    endfunction

    function logic calculate_scl(
            input i2c_state state, input logic [1:0] quad
    );
        case (state)
        I2C_IDLE: return 1'b1;
        I2C_START: return 1'b1;
        I2C_REPEATED_START: return 1'b1;
        default: return quad[1]; // Off first half, on second half
        endcase
    endfunction

    always_comb begin
        cycle_clear = (cs == I2C_IDLE);
        cycle_enable = (cs != I2C_IDLE);

        quad_clear = (cs == I2C_IDLE);
        quad_enable = cycle_done;

        bit_clear = (cs == I2C_IDLE);
        bit_enable = quad_done;

        sda_shift_enable = bit_done;

        sda_load_value = calculate_sda_sequence(cs, command_stream.data);

        scl_out = calculate_scl(cs, current_quad);
        sda_out = calculate_sda(cs, current_quad, sda_past, sda_present);
    end
    

endmodule


module rv_i2c_phy_tx_tb();

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    rv_i2c_command_stream_intf command_stream();
    rv_i2c_result_stream_intf result_stream();

    logic [9:0] cycles = 10'd250;
    logic [10:0] delay = 11'd0;

    rv_io_intf sda();
    rv_io_intf scl();

    rv_i2c_phy_tx rv_i2c_phy_inst (.*);

    initial begin
        // ...
        while (rst) @ (posedge clk);


    end

endmodule