`ifndef __RV_I2C__
`define __RV_I2C__

`include "../lib/rv_util.svh"

package rv_i2c;

	typedef enum logic {
	    RV_I2C_WRITE = 1'b0,
	    RV_I2C_READ = 1'b1
	} rv_i2c_op;

	typedef enum logic {
	    RV_I2C_SUCCESS = 1'b0,
	    RV_I2C_ACK_FAILURE = 1'b1
	} rv_i2c_status;

	typedef enum logic {
	    RV_I2C_8 = 1'b0,
	    RV_I2C_16 = 1'b1
	} rv_i2c_size;

	typedef struct packed {
	    rv_i2c_op op;
	    rv_i2c_size addr_size;
	    rv_i2c_size data_size;
	    logic [6:0] device;
	    logic [15:0] addr, data;
	} rv_i2c_command;

	typedef struct packed {
	    rv_i2c_status status;
	    logic [15:0] data;
	} rv_i2c_result;

endpackage

`endif
