`timescale 1ns/1ps

`include "../lib/rv_util.svh"
`include "../lib/rv_i2c.svh"
`include "../lib/rv_axi4_lite.svh"

`BUILD_STREAM_INTF_PACKAGED(rv_i2c, rv_i2c_command)
`BUILD_STREAM_INTF_PACKAGED(rv_i2c, rv_i2c_result)

/*
rv_i2c_controller:

TODO: Add interrupt support

Implements a simple I2C controller managed by an AXI4-Lite bus, and
consumes 4kB or 10 bits of address space.

Register Map:
    Addr  Name                       Bitfield
    'h0:  Status (R)                 {30'b0, ACK_ERROR, BUSY}
    'h4:  Device (R/W)               {25'b0, DEVICE[6:0]}
    'h8:  Read Result (R)            {16'b0, RESULT[15:0]}
    'hC:  Timing (R/W)               {6'b0, DELAY[9:0], 6'b0, CYCLES[9:0]}

    'h10: Write 8 Addr, 8 Data (W)   {8'b0, ADDR[7:0], 8'b0, DATA[7:0]}
    'h14: Write 8 Addr, 16 Data (W)  {8'b0, ADDR[7:0], DATA[15:0]}
    'h18: Write 16 Addr, 8 Data (W)  {ADDR[15:0], 8'b0, DATA[7:0]}
    'h1C: Write 16 Addr, 16 Data (W) {ADDR[15:0], DATA[15:0]}

    'h20: Read 8 Addr, 8 Data (W)    {8'b0, ADDR[7:0], 8'b0, DATA[7:0]}
    'h24: Read 8 Addr, 16 Data (W)   {8'b0, ADDR[7:0], DATA[15:0]}
    'h28: Read 16 Addr, 8 Data (W)   {ADDR[15:0], 8'b0, DATA[7:0]}
    'h2C: Read 16 Addr, 16 Data (W)  {ADDR[15:0], DATA[15:0]}
*/
module rv_i2c_controller #(
    parameter logic [9:0] DEFAULT_CYCLES = 10'd249, // (100 MHz / 400 kHz)
    parameter logic [9:0] DEFAULT_DELAY = 10'd0
)(
    input logic clk, rst,
    
    rv_axi4_lite_aw_intf.in axi_aw,
    rv_axi4_lite_w_intf.in  axi_w,
    rv_axi4_lite_b_intf.out axi_b,
    rv_axi4_lite_ar_intf.in axi_ar,
    rv_axi4_lite_r_intf.out axi_r,

    rv_io_intf.out sda,
    rv_io_intf.out scl
);

    import rv_mem::*;
    import rv_i2c::*;

    logic [9:0] cycles, delay;

    rv_mem_intf mem_command(.clk, .rst);
    rv_mem_intf mem_result(.clk, .rst);

    rv_axi4_lite_slave rv_axi4_lite_slave_inst(
        .clk, .rst,
        .axi_aw, .axi_w, .axi_b, .axi_ar, .axi_r,
        .mem_command, .mem_result
    );
    
    rv_i2c_command_stream_intf command_stream(.clk, .rst);
    rv_i2c_result_stream_intf result_stream(.clk, .rst);

    rv_i2c_phy_tx rv_i2c_phy_tx_inst(
        .clk, .rst,
        .command_stream, .result_stream,
        .cycles, .delay,
        .sda, .scl
    );

    rv_i2c_register_map  #(
        .DEFAULT_CYCLES(DEFAULT_CYCLES),
        .DEFAULT_DELAY(DEFAULT_DELAY)
    ) rv_i2c_register_map_inst (
        .clk, .rst,
        .mem_command, .mem_result,
        .command_stream, .result_stream,
        .cycles, .delay
    );

endmodule

module rv_i2c_register_map #(
    parameter logic [9:0] DEFAULT_CYCLES = 10'd249, // (100 MHz / 400 kHz)
    parameter logic [9:0] DEFAULT_DELAY = 10'd0
)(
    input logic clk, rst,
    
    rv_mem_intf.in mem_command,
    rv_mem_intf.out mem_result,

    rv_i2c_command_stream_intf.out command_stream,
    rv_i2c_result_stream_intf.in result_stream,

    output logic [9:0] cycles, delay
);

    import rv_mem::*;
    import rv_i2c::*;

    typedef struct packed {
        logic ack_error;
        logic busy;
    } i2c_status_flags;

    // Current State
    i2c_status_flags current_status;
    logic [6:0] current_device;
    logic [15:0] current_result;

    function automatic logic is_i2c_command(input logic [9:0] addr);
        return addr == 'h10 || addr == 'h14 || addr == 'h18 || addr == 'h1C ||
                addr == 'h20 || addr == 'h24 || addr == 'h28 || addr == 'h2C;
    endfunction

    function automatic rv_i2c_command get_i2c_command(
        input logic [9:0] addr,
        input logic [31:0] data,
        input logic [6:0] current_device
    );
        rv_i2c_command cmd;

        cmd.device = current_device;
        cmd.addr = data[31:16];
        cmd.data = data[15:0];
        // 'h10, 'h14, 'h18, 'h1C
        cmd.op = (addr[4] == 'h1) ? RV_I2C_WRITE : RV_I2C_READ;
        // 'h10, 'h14, 'h20, 'h24
        cmd.addr_size = (addr[3] == 'h0) ? RV_I2C_8 : RV_I2C_16;
        // 'h10, 'h18, 'h20, 'h28
        cmd.data_size = (addr[2] == 'h0) ? RV_I2C_8 : RV_I2C_16;

        return cmd;
    endfunction

    // HAZARD: Sequence memory results, relies on on AXI4-Lite slave ordering
    always_ff @ (posedge clk) begin
        mem_result.addr <= mem_command.addr;
        case (mem_command.addr[9:0])
        'h0: mem_result.data <= {30'b0, current_status};
        'h4: mem_result.data <= {25'b0, current_device};
        'h8: mem_result.data <= {16'b0, current_result};
        'hC: mem_result.data <= {6'b0, delay, 6'b0, cycles};
        default: mem_result.data <= 'b0;
        endcase
    end

    // Handle writes to the registers
    always_ff @ (posedge clk) begin
        if (rst) begin
            current_status <= '{ack_error: 'b0, busy: 'b0};
            current_device <= 'b0;
            current_result <= 'b0;
            cycles <= DEFAULT_CYCLES;
            delay <= DEFAULT_DELAY;
            command_stream.data <= '{default: 'b0};
        end else begin
            // Handle memory writes
            if (mem_command.valid && mem_command.op == RV_MEM_WRITE) begin
                // Update Read/Write Registers
                case (mem_command.addr[9:0])
                'h4: current_device <= mem_command.data[6:0];
                'hC: {delay, cycles} <= {mem_command.data[25:16], mem_command.data[9:0]};
                endcase

                // Start I2C operation from Write-Only Registers
                if (is_i2c_command(mem_command.addr[9:0]) && !current_status.busy) begin
                    current_status.busy <= 1'b1;
                    command_stream.data <= get_i2c_command(mem_command.addr, 
                            mem_command.data, current_device);
                end
            end
        
            // Clear busy and set results
            if (result_stream.valid) begin
                current_status.busy <= 1'b0;
                current_status.ack_error <= result_stream.data.status;
                current_result <= result_stream.data.data;
            end
        end
    end

    always_comb begin
        // Always accept memory requests
        mem_command.ready = 1'b1;

        // Always provide memory results
        mem_result.valid = 1'b1;
        mem_result.op = RV_MEM_READ;

        // Always accept i2c results
        result_stream.ready = 1'b1;

        // Run command stream
        command_stream.valid = current_status.busy;
    end

endmodule

// TODO: Support multi-master arbitration
module rv_i2c_phy_tx #()(
    input logic clk, rst,

    rv_i2c_command_stream_intf.in command_stream,
    rv_i2c_result_stream_intf.out result_stream,

    input logic [9:0] cycles,
    input logic [9:0] delay,

    rv_io_intf.out sda,
    rv_io_intf.out scl  
);

    /*
    () Indicates the state can repeat for both MSB and LSB
    Write:
        IDLE -> START -> DEVICE_WRITE -> (WRITE_ADDR) -> (WRITE_DATA) -> STOP
    Read:
        IDLE -> START -> DEVICE_WRITE -> (WRITE_ADDR) -> REPEATED_START -> DEVICE_READ -> (READ_DATA) -> STOP 
    */

    import rv_i2c::*;

    // I2C is an open drain driver and when T is low, the output is enabled
    assign {scl.o, sda.o} = 2'b00;

    logic enable, command_block, result_block;
    rv_seq_flow_controller #(
        .NUM_INPUTS(1),
        .NUM_OUTPUTS(1)
    ) flow_controller (
        .clk, .rst, .enable(enable),
        .inputs_valid({command_stream.valid}), 
        .inputs_ready({command_stream.ready}),
        .inputs_block({command_block}),

        .outputs_valid({result_stream.valid}),
        .outputs_ready({result_stream.ready}),
        .outputs_block({result_block})
    );

    typedef enum logic [3:0] {
        I2C_IDLE,
        I2C_START, I2C_REPEATED_START, I2C_STOP,
        I2C_DEVICE_WRITE, I2C_DEVICE_READ,
        I2C_WRITE_ADDR_MSB, I2C_WRITE_ADDR_LSB, 
        I2C_WRITE_DATA_MSB, I2C_WRITE_DATA_LSB, 
        I2C_READ_DATA_MSB, I2C_READ_DATA_LSB
    } i2c_state;

    // State update logic
    i2c_state cs, ns;
    logic next_scl;
    always_ff @ (posedge clk) begin
        if (rst) begin
            cs <= I2C_IDLE;
            scl.t <= 1'b1;
        end else if (enable) begin
            cs <= ns;
            scl.t <= next_scl;
        end
    end

    logic cycle_enable, cycle_clear, cycle_counter_done;
    logic [9:0] current_cycle;
    rv_counter #(.WIDTH(10)) cycle_counter_inst (
        .clk, .rst,
        .enable(cycle_enable), .clear(cycle_clear),
        .value(current_cycle),
        .max(cycles), .complete(cycle_counter_done)
    );

    logic quad_enable, quad_clear, quad_counter_done;
    logic [1:0] current_quad;
    rv_counter #(.WIDTH(2)) quad_counter_inst (
        .clk, .rst,
        .enable(quad_enable), .clear(quad_clear),
        .value(current_quad),
        .max(2'b11), .complete(quad_counter_done)
    );

    // 0 - 7 are transmitted bits and 8 is ack/nack
    logic bit_enable, bit_clear, bit_counter_done;
    logic [3:0] current_bit;
    rv_counter #(.WIDTH(4)) bit_counter_inst (
        .clk, .rst,
        .enable(bit_enable), .clear(bit_clear),
        .value(current_bit),
        .max(4'd8), .complete(bit_counter_done)
    );

    // SDA is produced by a shift register
    logic sda_shift_enable, sda_load_enable;
    // logic [8:0] sda_load_value;
    rv_shift_register #(
        .WIDTH(9),
        .RESET(9'b111111111)
    ) sda_shift_register_inst (
        .clk, .rst,

        .enable(sda_shift_enable),
        .load_enable(sda_load_enable),
        .load_value(calculate_sda_sequence(cs, command_stream.data)),

        .shift_out(sda.t)
    );

    logic sda_in_clear_enable;
    logic sda_in_shift_enable;
    logic [15:0] sda_in_value;
    rv_shift_register #(
        .WIDTH(16)
    ) sda_in_shift_register_inst (
        .clk, .rst,

        .enable(sda_in_shift_enable),
        .value(sda_in_value),
        .shift_in(sda.i),

        .load_enable(sda_in_clear_enable)
    );

    // Error sticky bit
    logic set_ack_error, clear_ack_error;
    always_ff @(posedge clk) begin
        if(rst || clear_ack_error) begin
            result_stream.data.status <= RV_I2C_SUCCESS;
        end else if (set_ack_error) begin
            result_stream.data.status <= RV_I2C_ACK_FAILURE;
        end
    end

    function logic [8:0] calculate_sda_sequence(
            input i2c_state state, input rv_i2c_command command
    );
        case (state)
        I2C_IDLE:           return {9'b111111111};
        I2C_START:          return {9'b000000000}; // Accelerated clocking, half cycle
        I2C_REPEATED_START: return {9'b110000000}; // Accelerated clocking, full cycle
        I2C_STOP:           return {9'b001111111}; // Accelerated clocking, full cycle

        I2C_DEVICE_WRITE:   return {command.device, RV_I2C_WRITE, 1'b1}; // Ends with slave ACK
        I2C_DEVICE_READ:    return {command.device, RV_I2C_READ, 1'b1}; // Ends with slave ACK

        I2C_WRITE_ADDR_MSB: return {command.addr[15:8], 1'b1}; // Ends with slave ACK
        I2C_WRITE_ADDR_LSB: return {command.addr[7:0], 1'b1}; // Ends with slave ACK

        I2C_WRITE_DATA_MSB: return {command.data[15:8], 1'b1}; // Ends with slave ACK
        I2C_WRITE_DATA_LSB: return {command.data[7:0], 1'b1}; // Ends with slave ACK

        I2C_READ_DATA_MSB:  return {9'b111111110}; // Ends with master ACK
        I2C_READ_DATA_LSB:  return {9'b111111111}; // Ends with master NACK
        default:            return {9'b111111111};
        endcase
    endfunction

    logic half_bit_done, full_bit_done, halfword_addr, halfword_data, op_read;

    always_comb begin

        half_bit_done = cycle_counter_done && current_quad == 2'b01;
        full_bit_done = quad_counter_done;

        halfword_addr = (command_stream.data.addr_size == RV_I2C_16);
        halfword_data = (command_stream.data.data_size == RV_I2C_16);

        op_read = (command_stream.data.op == RV_I2C_READ);

        if (cs == I2C_IDLE) begin
            ns = I2C_START;
        end else if (cs == I2C_START && half_bit_done) begin // Half bit state
            ns = I2C_DEVICE_WRITE;
        end else if (cs == I2C_REPEATED_START && full_bit_done) begin // Full bit state
            ns = I2C_DEVICE_READ;
        end else if (cs == I2C_STOP && full_bit_done) begin // Full bit state
            ns = I2C_IDLE;
        end else if (bit_counter_done) begin // Full byte state
            case (cs)
            I2C_DEVICE_WRITE:   ns = (halfword_addr ? I2C_WRITE_ADDR_MSB : I2C_WRITE_ADDR_LSB);
            I2C_DEVICE_READ:    ns = (halfword_data ? I2C_READ_DATA_MSB : I2C_READ_DATA_LSB);
            I2C_WRITE_ADDR_MSB: ns = I2C_WRITE_ADDR_LSB;
            I2C_WRITE_ADDR_LSB: ns = (op_read ? I2C_REPEATED_START : (halfword_data ? I2C_WRITE_DATA_MSB : I2C_WRITE_DATA_LSB));
            I2C_WRITE_DATA_MSB: ns = I2C_WRITE_DATA_LSB;
            I2C_WRITE_DATA_LSB: ns = I2C_STOP;
            I2C_READ_DATA_MSB:  ns = I2C_READ_DATA_LSB;
            I2C_READ_DATA_LSB:  ns = I2C_STOP;
            default:            ns = cs;
            endcase
        end else begin
            ns = cs;
        end

        cycle_enable = (cs != I2C_IDLE);
        quad_enable = cycle_counter_done;
        bit_enable = quad_counter_done;

        // Clear all counters when moving to the next state
        cycle_clear = (cs == I2C_IDLE) || (cs != ns);
        quad_clear = (cs == I2C_IDLE) || (cs != ns); 
        bit_clear = (cs == I2C_IDLE) || (cs != ns);
        
        // Shift SDA a quarter cycle past SCL falling edge
        if (cs == I2C_IDLE) begin
            sda_shift_enable = 1'b0;
            sda_load_enable = 1'b0;
        end else if (cs == I2C_START || cs == I2C_REPEATED_START || 
                cs == I2C_STOP) begin // Accelerated clocking
            sda_shift_enable = cycle_counter_done;
            sda_load_enable = cycle_counter_done && (current_quad == 2'b00);
        end else begin
            sda_shift_enable = cycle_counter_done && (current_quad == 2'b00);
            sda_load_enable = cycle_counter_done && (current_quad == 2'b00) && (current_bit == 4'b0); 
        end

        // Start SCL high and then toggle every two quads
        if (ns == I2C_IDLE || ns == I2C_START) begin
            next_scl = 1'b1;
        end else begin
            if (cycle_counter_done && (current_quad == 2'b01 || current_quad == 2'b11)) begin
                next_scl = ~scl.t;
            end else begin
                next_scl = scl.t;
            end
        end

        // Handle reading in SDA on the during the last half of SCL high
        sda_in_clear_enable = (cs == I2C_IDLE);
        sda_in_shift_enable = 1'b0;
        if (cs == I2C_READ_DATA_MSB || cs == I2C_READ_DATA_LSB) begin
            if (current_cycle == delay &&  current_quad == 2'b11 && current_bit != 4'd8) begin
                sda_in_shift_enable = 1'b1;
            end
        end
        result_stream.data.data = sda_in_value;

        // Handle reading in ACK confirmation on the last bit of each write cycle
        clear_ack_error = (cs == I2C_IDLE);
        set_ack_error = 1'b0;
        if (cs == I2C_DEVICE_WRITE || cs == I2C_DEVICE_READ ||
                cs == I2C_WRITE_ADDR_MSB || cs == I2C_WRITE_ADDR_LSB ||
                cs == I2C_WRITE_DATA_MSB || cs == I2C_WRITE_DATA_LSB) begin
            if (current_cycle == delay &&  current_quad == 2'b11 && current_bit == 4'd8) begin
                set_ack_error = (sda.i == 1'b1);
            end
        end

        // Only accept commands when in IDLE
        command_block = (cs == I2C_IDLE);
        // Only generate results when at end of stop
        result_block = (cs == I2C_STOP) && quad_counter_done;
    end

endmodule

module rv_i2c_phy_tx_tb();

    import rv_i2c::*;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    rv_i2c_command_stream_intf command_stream(.clk, .rst);
    rv_i2c_result_stream_intf result_stream(.clk, .rst);

    logic [9:0] cycles = 10'd1;
    logic [9:0] delay = 10'd0;

    rv_io_intf sda();
    rv_io_intf scl();

    rv_i2c_phy_tx rv_i2c_phy_inst (.*);

    rv_i2c_command cmd_temp;
    rv_i2c_result result_temp;

    initial begin
        command_stream.valid = 1'b0;
        result_stream.ready = 1'b0;
        while (rst) @ (posedge clk);
        for (int i = 0; i < 10; i++) @ (posedge clk);

        cmd_temp = '{
            op: RV_I2C_WRITE, 
            addr_size: RV_I2C_8, 
            data_size: RV_I2C_8,
            device: 7'b1101010,
            addr: 16'hee,
            data: 16'h55,
            default: 'b0
        };

        fork
            command_stream.send(cmd_temp);
            result_stream.recv(result_temp);
        join

        cmd_temp = '{
            op: RV_I2C_READ, 
            addr_size: RV_I2C_8, 
            data_size: RV_I2C_8,
            device: 7'b1101010,
            addr: 16'hee,
            data: 16'h55,
            default: 'b0
        };

        fork
            command_stream.send(cmd_temp);
            result_stream.recv(result_temp);
        join
    end

    initial begin
        sda.i = 'b1;

        while ('b1) begin
            @ (posedge scl.t);
            sda.i <= ~sda.i;
        end

    end

endmodule

module rv_i2c_controller_tb();

    import rv_axi4_lite::*;
    import rv_i2c::*;

    logic clk, rst;
    clk_rst_gen clk_rst_gen_inst(.clk, .rst);

    rv_axi4_lite_aw_intf axi_aw(.clk, .rst);
    rv_axi4_lite_w_intf  axi_w(.clk, .rst);
    rv_axi4_lite_b_intf  axi_b(.clk, .rst);
    rv_axi4_lite_ar_intf axi_ar(.clk, .rst);
    rv_axi4_lite_r_intf  axi_r(.clk, .rst);

    rv_io_intf sda();
    rv_io_intf scl();

    rv_i2c_controller rv_i2c_controller_inst(.*);


    logic [31:0] data_result;
    rv_axi4_lite_resp resp_result;

    task read(input logic [31:0] addr, 
            output logic [31:0] data, 
            output rv_axi4_lite_resp resp);
        axi_ar.send(addr, rv_axi4_lite_prot'(3'b0));
        axi_r.recv(data, resp);
    endtask

    task write(input logic [31:0] addr, 
            input logic [31:0] data, 
            output rv_axi4_lite_resp resp);
        fork
            axi_aw.send(addr, rv_axi4_lite_prot'(3'b0));
            axi_w.send(data, 'hf);
        join
        axi_b.recv(resp);
    endtask

    initial begin
        axi_aw.AWVALID = 'b0;
        axi_w.WVALID = 'b0;
        axi_b.BREADY = 'b0;
        axi_ar.ARVALID = 'b0;
        axi_r.RREADY = 'b0;
        while (rst) @ (posedge clk);

        // Check status
        read('h0, data_result, resp_result);

        // Set Device
        write('h4, 'h42, resp_result);

        // Check status
        read('h0, data_result, resp_result);        

        // Read Device
        read('h4, data_result, resp_result);

        // Read Timing
        read('hC, data_result, resp_result);

        // Start 8x8 Write
        write('h10, {8'b0, 8'hee, 8'b0, 8'h55}, resp_result);

        do begin
            read('h0, data_result, resp_result);
        end while (data_result[0]);
    end

endmodule
