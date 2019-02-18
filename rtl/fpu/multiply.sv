module FPU_add();


  always_comb begin
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