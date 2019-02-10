module FPU_div(
  input  logic [31:0] A, B,
  output logic [31:0] Y);

  logic [46:0] Y_quotient;
  logic [23:0] A_sig, B_sig;
  logic [8:0] Y_exp, diff;
  logic [7:0] A_exp, B_exp;
  logic [5:0] Y_zeroes;
  logic [2:0] guard; 
  logic normA, normB, nanA, nanB, zeroA, zeroB, infA, infB, exp_neg;
  logic overflow, underflow, A_sign, B_sign, exp_zeroA, exp_zeroB;

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

    exp_zeroA = (A_exp==0);
    exp_zeroB = (B_exp==0);

    exp_neg = 0;
    //Divide exponents
    if (A_exp >= B_exp) Y_exp = A_exp + exp_zeroA - B_exp - exp_zeroB;
    else begin
      Y_exp = B_exp + exp_zeroB - A_exp - exp_zeroA;
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
    divide(A_sig, B_sig, Y_quotient, guard); 
    LeadingZeros_47 (Y_quotient, Y_zeroes);

    //normalize
    if (Y_zeroes < 23) begin
      diff = 23-Y_zeroes;
      Y_quotient = Y_quotient >> diff;
      if (diff >= 255-Y_exp && !exp_neg) overflow = 1;
      else begin
        if (exp_neg) Y_exp -= diff; 
        else Y_exp += diff;
      end
    end else if (Y_zeroes >= 23) begin
      diff = Y_zeroes - 23;
      Y_quotient = Y_quotient << diff;
      if (diff > Y_exp && exp_neg) underflow = 1;
      else begin
        if (exp_neg) Y_exp += diff;
        else Y_exp -= diff;
      end
    end 

    round(Y_quotient[23:0], Y_exp, guard, exp_neg, Y[30:0]);
    //Y_sig = Y_quotient[26:0];

    //Y[22:0] = Y_quotient[22:0];
    //Y[30:23] = (exp_neg) ? (127 - Y_exp) : (Y_exp + 127);

    if (nanA || nanB || zeroB || infB) Y = 32'h7FFFFFFF;
    else if (overflow || infA) Y[30:0] = 31'h7F800000;
    else if (underflow || zeroA) Y = 0;
  end

endmodule

module test_divide();
  logic [31:0] A, B, Y, result, i;
	logic r;

  parameter NUM_VECTORS=10;
	logic [99:0] vectors [NUM_VECTORS-1:0];
	logic [99:0] args;
	
  FPU_div d(.*);

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

//3e3d15f6
