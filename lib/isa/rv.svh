`ifndef __RV__
`define __RV__

package rv;

    typedef logic [15:0] rv_inst_header_t;

	typedef enum logic [2:0] { 
        RV_INST_SIZE_16 = 3'b000,
        RV_INST_SIZE_32 = 3'b001,
        RV_INST_SIZE_48 = 3'b010,
        RV_INST_SIZE_64 = 3'b011,
        RV_INST_SIZE_VAR = 3'b100,
        RV_INST_SIZE_RESERVED = 3'b101
    } rv_inst_size_t;

    function automatic rv_inst_size_t rv_get_inst_size(
        input rv_inst_header_t inst_header
    );
        if (inst_header[1:0] != 2'b11) begin
            return RV_INST_SIZE_16;
        end else if (inst_header[4:2] != 3'b111) begin
            return RV_INST_SIZE_32;
        end else if (inst_header[5] == 1'b0) begin
            return RV_INST_SIZE_48;
        end else if (inst_header[6] == 1'b0) begin
            return RV_INST_SIZE_64;
        end else if (inst_header[14:12] != 3'b111) begin
            return RV_INST_SIZE_VAR;
        end else begin
            return RV_INST_SIZE_RESERVED;
        end
    endfunction

    function automatic logic [3:0] rv_get_inst_size_variable_parcels(
    		input rv_inst_header_t inst_header
    );
        return inst_header[14:12] + 4'd5;
    endfunction

endpackage

`endif
