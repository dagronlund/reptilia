`ifndef __FPU_OPS__ 
`define __FPU_OPS__

function automatic logic[47:0] fpu_operations_multiply(
    input  logic [23:0] a, b);

    return a*b;
endfunction

function automatic fpu_division_result_t fpu_operations_divide(
    input  logic [23:0] a, b);
    
    logic [5:0] i;
    logic [71:0] A, A2, x;

    fpu_division_result_t result;

    A = a<<24;
    for (i=0; i<48; i++) begin
        x = B<<(47-i);
        if (x<=A) begin
        A = A - x;
        result.quotient[47-i] = 1;
        end else begin
        result.quotient[47-i] = 0;
        end;
    end

    A2 = A<<3;
    for (i=0;i<3;i++) begin
        x = B<<(2-i);
        if (x<=A2) begin
        A2 = A2 - x;
        result.guard[2-i] = 1;
        end else begin
        result.guard[2-i] = 0;
        end
    end 
    
    return result;
endfunction



`endif