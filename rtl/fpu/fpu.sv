module riscv_FPU();

    FPU_decode Fdecode(.clk, .rst, .decode_signals);
    FPU_add Fadd(.clk, .rst, .decode_signals);
    FPU_mult Fmult(.clk, .rst, .decode_signals);
    FPU_divide Fdiv(.clk, .rst, .decode_signals);
    FPU_sqrt Fsqrt(.clk, .rst, .decode_signals);
    FPU_encoder Fencoder(.clk, .rst, .decode_signals);
    FPU_decoder Fdecoder(.clk, .rst, .decode_signals);

endmodule

module FPU_decode();

    always_ff @(posedge clk, negedge rst_l) begin
        if(!rst_l) begin
            signals_out <= '{default: 'b0};
        end else if (clk_en) begin
            signals_out <= signals_next;
        end
    end

    always_comb begin
        instr_info.opcode = instr[6:0];
        instr_info.rd = instr[11:7];
        instr_info.rm = instr[14:12];
        instr_info.rs1 = instr[19:15];
        instr_info.rs2 = instr[24:20];
        instr_info.funct7 = instr[31:25];
        instr_info.funct3 = instr[14:12];
        instr_info.funct5 = instr[24:20];
        instr_info.rs3 = instr[31:27];

        case(instr_info.opcode)
            RV32F_FUNCT7_FLW: // David
            RV32F_FUNCT7_FSW: // What
            RV32F_FUNCT7_FMADD_S: // am
            RV32F_FUNCT7_FMSUB_S: // I
            RV32F_FUNCT7_FNMSUB_S: // To
            RV32F_FUNCT7_FNMADD_S: // Do
            RV32F_FUNCT7_FP_OP_S: begin
                case(instr_info.funct7)
                    RV32F_FUNCT7_FADD_S: begin 
                        signals.add_en = 1'b1;
                        signals.rd_we = 1'b1;
                        signals.round_en = 1'b1;
                    end

                    RV32F_FUNCT7_FSUB_S: begin // turn on adder
                        signals.add_en = 1'b1;
                        signals.rd_we = 1'b1;
                        signals.round_en = 1'b1;
                        invert_sign = 1'b1;
                    end
                    RV32F_FUNCT7_FMUL_S: begin // mult on
                        signals.mult_en = 1'b1;
                        signals.rd_we = 1'b1;
                        signals.round_en = 1'b1;
                    end
                    RV32F_FUNCT7_FDIV_S: begin // div on
                        signals.div_en = 1'b1;
                        signals.rd_we = 1'b1;
                        signals.round_en = 1'b1;
                    end
                    RV32F_FUNCT7_FSQRT_S: begin // sqrt on
                        signals.sqrt_en = 1'b1;
                        signals.rd_we = 1'b1;
                        signals.round_en = 1'b1;
                    end
                    RV32F_FUNCT7_FSGNJ_S: begin // mult on
                        case(instr_info.funct3)
                            RV32F_FUNCT3_FSGNJ_S: begin  
                            RV32F_FUNCT3_FSGNJN_S: begin
                            RV32F_FUNCT3_FSGNJX_S: begin
                        endcase
                    end
                    RV32F_FUNCT7_FMIN_MAX_S: begin
                        case(instr_info.funct3)
                            RV32F_FUNCT3_FMIN_S: begin // adder on
                                signals.add_en = 1'b1;
                                signals.rd_we = 1'b1;
                                signals.round_en = 1'b0;
                                signals.compare = 1'b1;
                                signals.max = 1'b0;
                            end
                            RV32F_FUNCT3_FMAX_S: begin // adder on
                                signals.add_en = 1'b1;
                                signals.rd_we = 1'b1;
                                signals.round_en = 1'b0;
                                signals.compare = 1'b1;
                                signals.max = 1'b1;
                            end
                        endcase
                    end
                    RV32F_FUNCT7_FCVT_W_S: begin
                        case(instr_info.funct5) 
                            RV32F_FUNCT5_FCVT_W: begin // decoder (float2int) on
                                signals.decoder_en = 1'b1;
                                signals.rd_we = 1'b1;
                                signals.round_en = 1'b0;
                                signals.int_signed = 1'b1;
                            end
                            RV32F_FUNCT5_FCVT_WU: begin // decoder (float2int) on
                                signals.decoder_en = 1'b1;
                                signals.rd_we = 1'b1;
                                signals.round_en = 1'b0;
                                signals.int_signed = 1'b0;
                            end
                        endcase  
                    end        
                    RV32F_FUNCT7_FMV_X_W: begin
                        case(instr_info.funct5)
                            RV32F_FUNCT3_FMV_X_W: begin // Decoder on 
                                signals.decoder_en = 1'b1;
                                signals.rd_we = 1'b1;
                                signals.round_en = 1'b0;
                                signals.move = 1'b1;
                            end

                            RV32F_FUNCT3_FCLASS_S: begin // decoder on

                        endcase
                    end
                    RV32F_FUNCT7_FCMP_S: begin
                        case(instr_info.funct3)
                            RV32F_FUNCT3_FLE_S: begin // adder on 
                                signals.add_en = 1'b1;
                                signals.rd_we = 1'b1;
                                signals.round_en = 1'b1;
                                signals.compare = 1'b1;
                            end
                            RV32F_FUNCT3_FGE_S: begin // adder on 
                                signals.add_en = 1'b1;
                                signals.rd_we = 1'b1;
                                signals.round_en = 1'b1;
                                signals.compare = 1'b1;
                            end
                            RV32F_FUNCT3_FEQ_S: begin // adder on 
                                signals.add_en = 1'b1;
                                signals.rd_we = 1'b1;
                                signals.round_en = 1'b1;
                                signals.compare = 1'b1;
                            end
                        endcase
                    end
                    RV32F_FUNCT7_FCVT_S_W: begin
                        case(instr_info.funct5) 
                            RV32F_FUNCT5_FCVT_W: begin // encoder (int2float) on
                                signals.encoder_en = 1'b1;
                                signals.rd_we = 1'b1;
                                signals.round_en = 1'b0;
                                signals.int_signed = 1'b1;
                            end
                            RV32F_FUNCT5_FCVT_WU: begin // encoder (int2float) on
                                signals.encoder_en = 1'b1;
                                signals.rd_we = 1'b1;
                                signals.round_en = 1'b0;
                                signals.int_signed = 1'b0;
                            end 
                        endcase 
                    end
                    RV32F_FUNCT7_FMV_W_X: begin // encoder on
                        signals.encoder = 1'b1;
                        signals.rd_we = 1'b1;
                        signals.round_en = 1'b0;
                        signals.move = 1'b1;
                    end
                endcase
            end
            RV32F_FUNCT7_UNDEF: // rip u
        endcase
    end

endmodule
