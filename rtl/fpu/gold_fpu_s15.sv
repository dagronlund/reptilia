`define FP_ADD  2'd0
`define FP_SUB  2'd1
`define FP_MULT 2'd2

`define NAN (32'hFFFFFFFF)

module GOLD_FPU (Y_reg, A_reg, B_reg, SEL_reg, clk, Valid);
`include "fpu_tasks.sv"

  output bit [31:0] Y_reg;
  input  bit [31:0] A_reg,B_reg;
  input  bit [1:0] SEL_reg;
  input  bit clk;
  output bit Valid;

  bit [31:0] A, B, Y;
  bit [1:0] SEL;

  bit [7:0] expA, expB, expY;
  bit [9:0] tempExpY;
  bit [26:0] sigA, sigB;
  bit [27:0] sigY;
  bit signA, signB, signY;
  bit overflow, underflow;
  bit diff_sign,exp_ovf,sticky;
  bit [47:0] mtmp;
  bit [7:0] i;
  bit [5:0] leading_zs;
  bit [6:0] leading_mzs;
  bit exp0;
  bit denormalRes;
  
  bit denormalA, denormalB;
  bit [8:0] expY_ex, expA_ex, expB_ex, expY_ex_neg;
  
  always_ff @ (posedge clk) begin
    A <= A_reg;
    B <= B_reg;
    Y_reg <= Y;
    SEL <= SEL_reg;
    Valid <= 1'b1;
  end

  always_comb begin

    sigA = 0;
    sigB = 0;
    underflow = 0;
    overflow = 0;
    sticky=0;
    {signA, expA, sigA[25:3]} = A[31:0];
    {signB, expB, sigB[25:3]} = B[31:0];
    sigA[26] = ( A[30:0] != 0 && expA != 8'h00);
    sigB[26] = ( B[30:0] != 0 && expB != 8'h00);
    
    denormalA = ( A[30:0] != 0 && expA == 8'h00);
    denormalB = ( B[30:0] != 0 && expB == 8'h00);
    
    diff_sign = signA ^ signB;
    
    {signY,sigY,expY} = 0;
    leading_zs = 0;
    leading_mzs = 0;
    i = 0;
    mtmp = 0;
    exp0 = 0;

    casex (SEL)
      // Case of FP_ADD, FP_SUB
      2'b0?: begin 
        /*****************************/                
        /* Handle Some special cases */
        /*****************************/
        signB = (SEL == `FP_SUB) ? ~signB : signB;
        if (expA == 8'hFF || expB == 8'hFF) begin
          if (expA == 8'hFF && A[22:0] != 0)
            {signY,expY,sigY[25:3]} = `NAN;
          else if (expB == 8'hFF && B[22:0] != 0)
            {signY,expY,sigY[25:3]} = `NAN;
          else if (expA == 8'hFF && expB != 8'hFF )
            {signY,expY,sigY[25:3]} = A;
          else if (expA != 8'hFF && expB == 8'hFF )
            {signY,expY,sigY[25:3]} = {signB, B[30:0]};
          else if (A[30:0] == B[30:0] && signA == signB)
            {signY,expY,sigY[25:3]} = A;
          else
            {signY,expY,sigY[25:3]} = `NAN;
        end
        else begin 
        
        /*********************************/    
        /* Do the complicated Arithmetic */
        /*********************************/

        diff_sign = signA ^ signB;
        i = (expA - expB);
           
        /* If both exponents are the same, don't shift */
        if (i == 0) begin
          sigB = sigB; sigA = sigA; 
          expA = expA; expB = expB;
          expY = expA;         
        /* If exponent of B is 0, align B with A */
        end else if (expB == 0) begin
          i = i - 1;
          getSticky_27(sigB, i[4:0], sticky);
          sigB = sigB >> i;
          sigB[0] = sigB[0] | sticky;
          expY = expA;
        end 
        /* If exponent of A is 0, align A with B */
        else if (expA == 0) begin
          i = ~i + 1;
          i = i - 1;
          getSticky_27(sigA, i[4:0], sticky);
          sigA = sigA >> i;
          sigA[0] = sigA[0] | sticky;
          expY = expB;
        /*  If B has the smaller exponent, right shift align it  */
        end else if (expA > expB) begin
          getSticky_27(sigB, i[4:0], sticky);
          sigB = sigB >> i;
          sigB[0] = sigB[0] | sticky;
          expY = expA;
        end 
        /*  If A has the smaller exponent, right shift align it  */
        else if (expA < expB) begin
          i = ~i+1;
          getSticky_27(sigA, i[4:0], sticky);
          sigA = sigA >> i;
          sigA[0] = sigA[0] | sticky;
          expY = expB;
        end




        /* Do the Addition/Subtraction */
        if (!diff_sign)
          sigY = {1'b0,sigA} + {1'b0,sigB};
        else if (signA)
          sigY = {1'b1,~sigA} + {1'b0,sigB} + 1;
        else 
          sigY = {1'b0,sigA} + {1'b1,~sigB} + 1;

        /* Set the final sign bit */
        if (diff_sign)
          signY = sigY[27];
        else
          signY = signA;
        
      
        /* Make positive again if needed */
        if (sigY[27] && diff_sign)
          sigY = ~sigY + 1;
        else
          sigY = sigY;
        
        /* Zero result if the significand is zero*/
        if(sigY==0) 
          expY=0;
        else 
          expY = expY;
            
        /**********************************/
        /* Correct for Addition overflow */
        /**********************************/
        if ( !diff_sign && sigY[27] ) begin
          sticky = sigY[0];
          sigY = sigY >> 1;
          sigY[0] = sticky | sigY[0];
          if (expY >= 254)
            overflow = 1;
          expY = expY+1;
        end
        else if (diff_sign) begin
          /* Right shifting for exponent adjustment */
          LeadingZeros_27(sigY[26:0],leading_zs);
          if (leading_zs < 27 && (expY > leading_zs) ) begin
            sigY = sigY << leading_zs;
            expY = expY - leading_zs;
          end
          else if (leading_zs < 27 && (expY < leading_zs)) begin
            if (expY > 0) begin
              sigY = sigY << (expY - 1);
            end
            expY = 0;
          end
          else if (leading_zs < 27 && (expY == leading_zs)) begin
            // Nothing for now?
            if (expY > 0)
              sigY = sigY << (expY-1);
            expY = 0;
          end
          else if (leading_zs >= 27) begin
            underflow=1;
            expY=0;
            sigY=0;
          end
        end

        /************************/
        /* Round the numbers */
        /************************/
        if (!sigY[2]) begin /* Truncate */
          {sigY,expY} = {sigY,expY};
        end  else if (sigY[2] && (|sigY[1:0])) begin /* Round Up */
          sigY[27:3] = sigY[27:3] + 1;
          if (sigY[27]) begin
            if (expY == 254)
              overflow = 1;
            sigY = sigY >> 1;
            expY = expY + 1;
          end
        end else begin // If guard bits are 100. 
          if (sigY[3]) begin
            sigY[27:3] = sigY[27:3] + 1;
            if (sigY[27]) begin
              if (expY >= 254)
                overflow = 1;
              sigY = sigY >> 1;
              expY = expY + 1;
            end
          end else begin
            {expY,sigY} = {expY,sigY};
          end  
        end
        
      
        if (overflow) begin /* If overflow, go to Infinity */
          expY = 8'hFF;  
          sigY = 0; 
        end else if (sigY == 0) /* If zero, zero out Exponent */
          expY = 0;
           if (expY == 0 && sigY[26])
             expY = 1;
           

      end /* finished Complicated Arithmetic */
      end /* End of Add/Sub Case */
      
      
      
      `FP_MULT: begin
        signY = diff_sign;
        exp0 = ((expA == 8'h7f) || (expB == 8'h7f));
        
        
        /* ----------------------------------------------------- */
        // Preprocess two operands
        
        if (denormalA)  sigA = sigA << 1;
        if (denormalB)  sigB = sigB << 1;
        
        
        /* ----------------------------------------------------- */
        // Determine underflow, overflow and demornalized result
        
        expA_ex = {1'b0, expA};
        expB_ex = {1'b0, expB};
        expY_ex = expA_ex + expB_ex - 9'h07f;  // equal to -8'h7f

        denormalRes = 0;
        overflow = 0;
        underflow = 0;
        
        
        if (~exp0) begin
          overflow = expA[7] && expB[7] && expY_ex[8];
          expY_ex_neg = ~expY_ex+1;
          underflow = ~expA[7] && ~expB[7] && expY_ex[8] && (expY_ex_neg >= 26);  // 26 or 27
        end
        
        
        
        /* ----------------------------------------------------- */
        // Multipliy operation
        
        mult_24(sigA[26:3], sigB[26:3], mtmp);
        //$display ("sigA = %b", sigA[26:3]);
        //$display ("sigB = %b", sigB[26:3]);
        //$display ("mtmp = %b", mtmp);
        
        /* ----------------------------------------------------- */
        // Normalize

        if (mtmp[47]) begin
          if (~expY_ex[8] && expY_ex[7:0] >= 254) begin
              overflow = 1;
          end
          mtmp = mtmp >> 1;
          expY_ex = expY_ex + 1;
        end
        
        LeadingZeros_47(mtmp[46:0], leading_mzs);
        
        //$display ("expY_ex = %b, -expY_ex = %b", expY_ex, ~expY_ex+1);
        if (leading_mzs < 47 && ~expY_ex[8] && expY_ex[7:0] > leading_mzs) begin
          mtmp = mtmp << leading_mzs;
          expY_ex = expY_ex - leading_mzs;
        end
        else if (leading_mzs < 47 && ~expY_ex[8] && expY_ex <= leading_mzs) begin
          mtmp = mtmp << expY_ex; 
          expY_ex = 0;
        end
        else if (leading_mzs < 47 && expY_ex[8]) begin
          expY_ex_neg = ~expY_ex+1;
          mtmp = mtmp >> expY_ex_neg;
          expY_ex = 0;
        end
        
        
        /* ----------------------------------------------------- */
        // Adjustment denormal number to exp=-126
        if (expY_ex == 0) begin
          mtmp = mtmp >> 1;
        end
        //$display ("mtmp = %b", mtmp);
        //$display ("sigY = %b", mtmp[45:23]);
        
        /* ----------------------------------------------------- */
        // Rounding
        
        /*
        // The afs machine uses 23 bits for rounding
        if (mtmp[22:0] == 23'b100_0000_0000_0000_0000_0000) begin
          // Round to even
          if (mtmp[23])  sigY[27:3] = mtmp[47:23] + 1;
          else  sigY[27:3] = mtmp[47:23];
        end 
        else if (mtmp[22:0] > 23'b100_0000_0000_0000_0000_0000) begin
          // Round up
          sigY[27:3] = mtmp[47:23] + 1;
        end 
        else if (mtmp[22:0] < 23'b100_0000_0000_0000_0000_0000) begin
          // Round down
          sigY[27:3] = mtmp[47:23];
        end
        */
        
        if (mtmp[22:20] == 3'b100) begin
          // Round to even
          if (mtmp[23])  sigY[27:3] = mtmp[47:23] + 1;
          else  sigY[27:3] = mtmp[47:23];
        end 
        else if (mtmp[22:20] > 3'b100) begin
          // Round up
          sigY[27:3] = mtmp[47:23] + 1;
        end 
        else if (mtmp[22:20] < 3'b100) begin
          // Round down
          sigY[27:3] = mtmp[47:23];
        end
        
        
        //$display ("sigY = %b", mtmp[45:23]);
        /* ----------------------------------------------------- */
        // Must check for overflow after round
        
        if (sigY[27]) begin
          if (~expY_ex[8] && expY_ex[7:0] >= 254)
            overflow = 1;
          sigY = sigY >> 1;
          expY_ex = expY_ex + 1;
        end
        else if (sigY[26] & expY_ex == 0) begin
          expY_ex = expY_ex + 1;
        end
        
        if (overflow || expY_ex == 9'h0FF) begin /* Set to infty */
          expY_ex = 9'h0FF;
          sigY = 0;
        end
        else if (underflow) begin /* Set to Zero */
          expY_ex = 0;
          sigY = 0;
        end
        /* If Zero happened then make zero */
        else if (sigY == 0)
          expY_ex = 0;
        
        
        /* ----------------------------------------------------- */
        // Change exponential back
        expY = expY_ex[7:0];



      
        /* In these special Cases */
        if (expA == 8'hFF || expB == 8'hFF) begin
          if (expA == 8'hFF && A[22:0] != 0)
            {signY,expY,sigY[25:3]} = `NAN;
          else if (expB == 8'hFF && B[22:0] != 0)
            {signY,expY,sigY[25:3]} = `NAN;
          else if (expA == 8'hFF && B[30:0] == 0)
            {signY,expY,sigY[25:3]} = `NAN;
          else if (expA == 8'hFF && expB != 8'hFF )
            {signY,expY,sigY[25:3]} = {A[31]^B[31], A[30:0]};
          else if (expB == 8'hFF && A[30:0] == 0)
            {signY,expY,sigY[25:3]} = `NAN;
          else if (expA != 8'hFF && expB == 8'hFF )
            {signY,expY,sigY[25:3]} = {A[31]^B[31], B[30:0]};
          else if (A[30:0] == B[30:0] )
            {signY,expY,sigY[25:3]} = {A[31] ^ B[31], A[30:0]};
          else
            {signY,expY,sigY[25:3]} = `NAN;
        end
        
      end
    endcase
    Y = {signY, expY, sigY[25:3]};
  end

endmodule : GOLD_FPU

