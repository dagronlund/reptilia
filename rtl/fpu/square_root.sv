`default_nettype none

module FPU_sqrt(
  input  logic [31:0] A,
  output logic [31:0] Y);

  logic [47:0] sig, temp, M, d;
  logic [23:0] mant;
  logic [7:0] exp, i, j;
  logic [2:0] guard;
  logic neg_exp, norm, is_zero, is_badnum; 

  always_comb begin 
    exp = A[30:23];
    norm = (exp!=0);
    mant = {norm, A[22:0]};
    is_zero = (A[30:0]==31'd0);
    is_badnum = (exp==8'hFF);

    //convert to actual exponent (excess 127)
    if (exp < 127) begin
      exp = (exp==0) ? 126: 127-exp;
      neg_exp = 1'd1;
    end else begin
      exp = exp - 127;
      neg_exp = 1'd0;
    end 

    //half the exponent
    if (exp[0]) begin //odd exponent
      if (neg_exp) sig = {2'd0, mant, 22'd0};
      else sig = {mant, 24'd0};
    end else
      sig = {1'd0, mant, 23'd0};

    exp = exp >> 1;

    square_root(sig, mant, guard);
    round(mant, {1'd0, exp}, guard, neg_exp, Y);

    //calculate square root
    // temp = 48'd0;
    // M = 48'd1;
    // for (i=0;i<24;i++) begin
    //   temp = {temp[45:0], sig[47:46]};
    //   sig = sig<<2;
    //   if (M <= temp) begin
    //     temp = temp-M;
    //     mant[23-i] = 1;
    //     d = M+1;
    //     M = {d[46:0], 1'd1};
    //   end else begin
    //     mant[23-i] = 1'd0;
    //     M = {M[46:1], 2'd1};
    //   end 
    // end

    //handle cases
    if(A[31] || is_badnum) Y = 32'hFFFFFFFF;
    else if (is_zero) Y = 32'd0;
    else begin 
      Y[31] = 1'd0;
    end 

  end

endmodule // square_root 

// module sqrt_testbench();
//   logic [31:0] A, Y, i;
//   logic [9:0][31:0] result;

//   assign result[0] = 32'h41c80000;
//   assign result[1] = 32'h3e000000;
//   assign result[2] = 32'h4043f58d;
//   assign result[3] = 0;
//   assign result[4] = 32'hFFFFFFFF;

//   FPU_sqrt sqrt(.*);

//   initial begin
//     $monitor($time,, "sqrt(%h) = %h Ans: %h", A, Y, result[i]);
//     i = 0;
//     A = 32'h441c4000;
//     #400
//     i = 1;
//     A = 32'h3c800000;
//     #400
//     i = 2;
//     A = 32'h41160000;
//     #400
//     i = 3;
//     A = 32'd0;
//     #400
//     i = 4;
//     A = 32'hc41c4000;
//     #400
//     $finish;
//   end

// endmodule

module test_divide();
  logic [31:0] A, B, Y, result, i;
  logic r;

  parameter NUM_VECTORS=10;
  logic [99:0] vectors [NUM_VECTORS-1:0];
  logic [99:0] args;
  
  FPU_sqrt d(.*);

  initial begin
    $readmemh("random_floats.vm", vectors);
    for(i=0;i<NUM_VECTORS;i++) begin
      args = vectors[i];
      A = args[95:64];
      B = args[63:32];
      result = args[31:0];
      #600
      r = (result==Y);
      $display($time,, "%h/%h = %h (%h) %b [%b]\n", A, B, Y, result, r, d.guard);
    end
    $finish;
  end

endmodule










