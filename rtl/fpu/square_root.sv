`default_nettype none

module square_root(
  input  logic [31:0] A,
  output logic [31:0] Y);

  logic [47:0] sig, temp, M, d;
  logic [23:0] mant;
  logic [7:0] exp, i, j;
  logic [1:0] v;
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

    temp = 48'd0;
    M = 48'd1;
    for (i=0;i<24;i++) begin
      temp = {temp[45:0], sig[47:46]};
      sig = sig<<2;
      if (M <= temp) begin
        temp = temp-M;
        mant[23-i] = 1;
        d = M+1;
        M = {d[46:0], 1'd1};
      end else begin
        mant[23-i] = 1'd0;
        M = {M[46:1], 2'd1};
      end 
    end

    if(A[31] || is_badnum) Y = 32'hFFFFFFFF;
    else if (is_zero) Y = 32'd0;
    else begin 
      Y[31] = 1'd0;
      Y[30:23] = (neg_exp) ? ~exp+128:exp+127;
      Y[22:0] = mant[22:0];
    end 

  end

endmodule // square_root 

module sqrt_testbench();
  logic [31:0] A, Y, i;
  logic [9:0][31:0] result;

  assign result[0] = 32'h41c80000;
  assign result[1] = 32'h3e000000;
  assign result[2] = 32'h4043f58d;
  assign result[3] = 0;
  assign result[4] = 32'hFFFFFFFF;

  square_root sqrt(.*);

  initial begin
    $monitor($time,, "sqrt(%h) = %h Ans: %h", A, Y, result[i]);
    i = 0;
    A = 32'h441c4000;
    #400
    i = 1;
    A = 32'h3c800000;
    #400
    i = 2;
    A = 32'h41160000;
    #400
    i = 3;
    A = 32'd0;
    #400
    i = 4;
    A = 32'hc41c4000;
    #400
    $finish;
  end

endmodule










