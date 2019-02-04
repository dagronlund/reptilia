module FPU_div(
  input  logic [31:0] A, B,
  output logic [31:0] Y);

  logic [46:0] Y_quotient;
  logic [23:0] A_sig, B_sig;
  logic [8:0] Y_exp, diff;
  logic [7:0] A_exp, B_exp;
  logic [5:0] Y_zeroes;
  logic normA, normB, nanA, nanB, zeroA, zeroB, infA, infB, exp_neg;
  logic overflow, underflow, A_sign, B_sign;


  always_comb begin
    {A_sign, A_exp, A_sig[22:0]} = A;
    {B_sign, B_exp, B_sig[22:0]} = B;


    normA = (A_exp != 8'd0);
    normB = (B_exp != 8'd0);
    nanA = (A==32'hFFFFFFFF);
    nanB = (B==32'hFFFFFFFF);
    zeroA = (A[30:0]==0);
    zeroB = (A[30:0]==0);
    infA = (A[30:0]==31'h7F800000);
    infB = (B[30:0]==31'h7F800000);

    Y[31] = A_sign ^ B_sign;
    A_sig[23] = normA;
    B_sig[23] = normB;

    exp_neg = 0;
    //Divide exponents
    if (A_exp > B_exp) Y_exp = A_exp - B_exp;
    else begin
      Y_exp = B_exp - A_exp;
      exp_neg = 1;
    end 

    //check for over/underflow
    overflow = 0;
    underflow = 0;
    if(Y_exp > 127) begin 
      if(exp_neg) underflow = 1;
      else overflow = 1;
    end 

    //divide mantissa
    divide(A_sig, B_sig, Y_quotient); 
    LeadingZeros_47 (Y_quotient, Y_zeroes);

    //normalize
    if (Y_zeroes < 23) begin
      diff = 23-Y_zeroes;
      Y_quotient = Y_quotient >> diff;
      if (diff >= 255-Y_exp) overflow = 1;
      else Y_exp += diff;
    end else if (Y_zeroes >= 24) begin
      diff = Y_zeroes - 23;
      Y_quotient = Y_quotient << diff;
      $display("oof");
      if (diff >= Y_exp) underflow = 1;
      else Y_exp -= diff;
    end 

    //Y_sig = Y_quotient[26:0];

    Y[22:0] = Y_quotient[22:0];
    Y[30:23] = (exp_neg) ? (127 - Y_exp) : (Y_exp + 127);

    if (nanA || nanB || zeroB || infB) Y = 32'h7FFFFFFF;
    else if (overflow || infA) Y[30:0] = 31'h7F800000;
    else if (underflow || zeroA) Y = 0;
  end

endmodule





module test_divide();
  logic [31:0] A, B, Y, r;

  FPU_div d(.*);

  initial begin
    $monitor($time,, "%h/%h = %h (%h, %d)\n", A, B, Y, d.Y_quotient, d.diff);
    A = 32'h441c4000;
    B = 32'h41c80000;
    #600
    A = 32'h44378000;
    B = 32'h45787000;
    #600
    $finish;
  end

endmodule

//3e3d15f6