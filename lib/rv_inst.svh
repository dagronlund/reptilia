`ifndef __RV_INST__
`define __RV_INST__

package rv_inst;

    parameter bit [6:0] FUNCT7_NORMAL = 7'b0000000;
    parameter bit [6:0] FUNCT7_ARITH_SHIFT = 7'b0100000;
    parameter bit [6:0] FUNCT7_SUB = 7'b0100000;
    parameter bit [6:0] FUNCT7_MUL_DIV = 7'b0000000;

    parameter bit [11:0] CSR_ECALL = 12'b000000000000;
    parameter bit [11:0] CSR_EBREAK = 12'b000000000001;

    parameter bit [11:0] CSR_FFLAGS = 12'h001;
    parameter bit [11:0] CSR_FRM = 12'h002;
    parameter bit [11:0] CSR_FCSR = 12'h003;

    parameter bit [11:0] CSR_CYCLE = 12'hC00;
    parameter bit [11:0] CSR_TIME = 12'hC01;
    parameter bit [11:0] CSR_INSTRET = 12'hC02;
    parameter bit [11:0] CSR_CYCLEH = 12'hC80;
    parameter bit [11:0] CSR_TIMEH = 12'hC81;
    parameter bit [11:0] CSR_INSTRETH = 12'hC82;

    typedef enum bit [2:0] { 
        RV_INST_SIZE_16 = 3'b000,
        RV_INST_SIZE_32 = 3'b001,
        RV_INST_SIZE_48 = 3'b010,
        RV_INST_SIZE_64 = 3'b011,
        RV_INST_SIZE_VAR = 3'b100,
        RV_INST_SIZE_RES = 3'b101
    } rv_inst_size;

    function automatic rv_inst_size rv_inst_get_size(bit [15:0] inst_header);
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
            return RV_INST_SIZE_RES;
        end
    endfunction

    function automatic bit [3:0] rv_inst_get_size_variable_parcels(bit [15:0] inst_header);
        return inst_header[14:12]) + 4'd5;
    endfunction

    typedef struct packed {
        // Normal Fields
        bit [6:0] opcode;
        bit [4:0] rd;
        bit [4:0] rs1;
        bit [4:0] rs2;
        bit [2:0] funct3;
        bit [6:0] funct7;

        // Special Fields
        bit [5:0] shift_amount;
        bit [3:0] pred;
        bit [3:0] succ;
        bit [11:0] csr;
        bit [4:0] zimm;
    } rv_inst_data_32;

    function automatic rv_inst_data_32 rv_inst_get_data_32(bit [31:0] inst);
        rv_inst_data_32 data = '{default:'0};
        
        data.opcode = inst[6:0];
        
        data.rd = inst[11:7];
        data.rs1 = inst[19:15];
        data.rs2 = inst[24:20];

        data.funct3 = inst[14:12];
        data.funct7 = inst[31:25];

        data.shift_amount = inst[24:20];

        data.pred = inst[27:24];
        data.succ = inst[23:20];

        data.csr = inst[31:20];
        data.zimm = inst[19:15];

        return data;
    endfunction

    typedef enum bit [2:0] {  
        RV_INST_TYPE_IR = 3'b000, // R uses no immediates, and I is the simplest
        RV_INST_TYPE_S = 3'b001,
        RV_INST_TYPE_U = 3'b010,
        RV_INST_TYPE_B = 3'b011, // Special case of S
        RV_INST_TYPE_J = 3'b100  // Special case of U
    } rv_inst_type_32;

    function automatic rv_inst_type rv_inst_get_type_32(rv_inst_data_32 data);
        case (data.opcode)
        7'b0110111: return RV_INST_TYPE_U;
        7'b0010111: return RV_INST_TYPE_U;
        7'b1100011: return RV_INST_TYPE_B;
        7'b0100011: return RV_INST_TYPE_S;
        7'b1101111: return RV_INST_TYPE_J;
        default: return RV_INST_TYPE_IR; // I and R are treated the same
        endcase
    endfunction

    function automatic bit[31:0] rv_inst_get_immediate_32(bit [31:0] inst);
        case (rv_inst_get_type_32(inst))
        RV_INST_TYPE_S: return {{20{inst[31]}}, inst[31:25], inst[11:7]};
        RV_INST_TYPE_B: return {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};
        RV_INST_TYPE_U: return {inst[31:12], 12'b0};
        RV_INST_TYPE_J: return {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
        default: return {{20{inst[31]}}, inst[31:20]}; // TYPE_IR
        endcase 
    endfunction

    typedef enum bit [7:0] {
        RV_LUI, RV_AUIPC, RV_JAL, RV_JALR,
        RV_BEQ, RV_BNE, RV_BLT, RV_BGE, RV_BLTU, RV_BGEU,
        RV_LB, RV_LH, RV_LW, RV_LBU, RV_LHU,
        RV_SB, RV_SH, RV_SW,
        RV_ADDI, RV_SLTI, RV_SLTIU, RV_XORI, RV_ORI, RV_ANDI, RV_SLLI, RV_SRLI, RV_SRAI,
        RV_ADD, RV_SUB, RV_SLL, RV_SLT, RV_SLTU, RV_XOR, RV_SRL, RV_SRA, RV_OR, RV_AND,
        RV_FENCE, RV_FENCE_I,
        RV_ECALL, RV_EBREAK,
        RV_CSRRW, RV_CSRRS, RV_CSRRC, RV_CSRRWI, RV_CSRRSI, RV_CSRRCI,
        RV_32I_UNDEF
    } rv_inst_32i;

    // Decodes the instruction type
    function rv_inst_32i rv_inst_32i_decode(rv_inst_data_32 data);
        case(data.opcode)
        7'b0110111: return RV_LUI;
        7'b0010111: return RV_AUIPC;
        7'b1101111: return RV_JAL;
        7'b1100111: 
            case(data.funct3)
            3'b000: return RV_JALR;
            default: return RV_32I_UNDEF;
            endcase
        7'b1100011:
            case(data.funct3)
            3'b000: return RV_BEQ;
            3'b001: return RV_BNE;
            3'b100: return RV_BLT;
            3'b101: return RV_BGE;
            3'b110: return RV_BLTU;
            3'b111: return RV_BGEU;
            default: return RV_32I_UNDEF;
            endcase
        7'b0000011:
            case(data.funct3)
            3'b000: return RV_LB;
            3'b001: return RV_LH;
            3'b010: return RV_LW;
            3'b100: return RV_LBU;
            3'b101: return RV_LHU;
            default: return RV_32I_UNDEF;
            endcase
        7'b0100011:
            case(data.funct3)
            3'b000: return RV_SB;
            3'b001: return RV_SH;
            3'b010: return RV_SW;
            default: return RV_32I_UNDEF;
            endcase
        7'b0010011:
            case(data.funct3)
            3'b000: return RV_ADDI;
            3'b001:
                case(data.funct7)
                FUNCT7_NORMAL: return RV_SLLI;
                default: return RV_32I_UNDEF;
                endcase
            3'b010: return RV_SLTI
            3'b011: return RV_SLTIU;
            3'b100: return RV_XORI;
            3'b101:
                case (data.funct7)
                FUNCT7_NORMAL: return RV_SRLI;
                FUNCT7_ARITH_SHIFT: return RV_SRAI;
                default: return RV_32I_UNDEF;
                endcase
            3'b110: return RV_ORI;
            3'b111: return RV_ANDI;
            endcase
        7'b0110011:
            case(data.funct3)
            3'b000:
                case(data.funct7)
                FUNCT7_NORMAL: return RV_ADD;
                FUNCT7_SUB: return RV_SUB;
                default: return RV_32I_UNDEF;
                endcase
            3'b001:
                case(data.funct7)
                FUNCT7_NORMAL: return RV_SLL;
                default: return RV_32I_UNDEF;
                endcase
            3'b010:
                case(data.funct7)
                FUNCT7_NORMAL: return RV_SLT;
                default: return RV_32I_UNDEF;
                endcase
            3'b011: 
                case(data.funct7)
                FUNCT7_NORMAL: return RV_SLTU;
                default: return RV_32I_UNDEF;
                endcase
            3'b100: 
                case(data.funct7)
                FUNCT7_NORMAL: return RV_XOR;
                default: return RV_32I_UNDEF;
                endcase
            3'b101:
                case(data.funct7)
                FUNCT7_NORMAL: return RV_SRL;
                FUNCT7_ARITH_SHIFT: return RV_SRA;
                default: return RV_32I_UNDEF;
                endcase
            3'b110:
                case(data.funct7)
                FUNCT7_NORMAL: return RV_OR;
                default: return RV_32I_UNDEF;
                endcase
            3'b111:
                case(data.funct7)
                FUNCT7_NORMAL: return RV_AND;
                default: return RV_32I_UNDEF;
                endcase
            endcase
        7'b0001111:
            if (data.rd != 5'b0 || data.rs1 != 5'b0 || data.funct7[6:3] != 4'b0) begin
                return RV_32I_UNDEF;
            end else begin
                case(data.funct3)
                3'b000: return RV_FENCE;
                3'b001:
                    if (data.pred != 4'b0 || data.succ != 4'b0) begin
                        return RV_32I_UNDEF;
                    end else begin
                        return RV_FENCE_I;
                    end
                default: return RV_32I_UNDEF;
                endcase
            end
        7'b1110011:
            case(data.funct3)
            3'b000:
                if (data.rd != 5'b0 || data.rs1 != 5'b0) begin
                    return RV_32I_UNDEF;
                end else begin
                    case(data.csr)
                    CSR_ECALL: return RV_ECALL;
                    CSR_EBREAK: return RV_EBREAK;
                    default: return RV_32I_UNDEF;
                    endcase
                end
            3'b001: return RV_CSRRW;
            3'b010: return RV_CSRRS;
            3'b011: return RV_CSRRC;
            3'b101: return RV_CSRRWI;
            3'b110: return RV_CSRRSI;
            3'b111: return RV_CSRRCI;
            default: return RV_32I_UNDEF;
            endcase
        default: return RV_32I_UNDEF;
        endcase
    endfunction

    typedef enum bit [3:0] {
        RV_MUL, RV_MULH, RV_MULHSU, RV_MULHU, RV_DIV, RV_DIVU, RV_REM, RV_REMU,
        RV_32M_UNDEF
    } rv_inst_32m;

    function rv_inst_32m rv_inst_32m_decode(rv_inst_data_32 data);
        case(data.opcode)
        7'b0110011:
            case(data.funct7)
            FUNCT7_MUL_DIV:
                case (data.funct3)
                3'b000 return MUL;
                3'b001 return MULH;
                3'b010 return MULHSU;
                3'b011: return MULHU;
                3'b100: return DIV;
                3'b101: return DIVU;
                3'b110: return REM;
                3'b111: return REMU;
                default: return RV_32M_UNDEF;
                endcase
            default: return RV_32M_UNDEF;
            endcase
        default: return RV_32M_UNDEF;
        endcase
    endfunction

    typedef enum bit [3:0] {
        RV_LR_W, RV_SC_W, 
        RV_AMOSWAP_W, RV_AMOADD_W, 
        RV_AMOXOR_W, RV_AMOAND_W, RV_AMOOR_W, 
        RV_AMOMIN_W, RV_AMOMAX_W, 
        RV_AMOMINU_W, RV_AMOMAXU_W,
        RV_32A_UNDEF
    } rv_inst_32a;

    function rv_inst_32a rv_inst_32a_decode(rv_inst_data_32 data);
        if (data.opcode == 7'b0101111 && data.funct3 == 3'b010) begin
            case (data.funct7[6:2])
            5'b00010: 
                if (data.rs2 == 5'b0) begin
                    return RV_LR_W;
                end else begin
                    return RV_32A_UNDEF;
                end
            5'b00011: return RV_SC_W;
            5'b00001: return RV_AMOSWAP_W;
            5'b00000: return RV_AMOADD_W;
            5'b00100: return RV_AMOXOR_W;
            5'b01100: return RV_AMOAND_W;
            5'b01000: return RV_AMOOR_W;
            5'b10000: return RV_AMOMIN_W;
            5'b10100: return RV_AMOMAX_W;
            5'b11000: return RV_AMOMINU_W;
            5'b11100: return RV_AMOMAXU_W;
            default: return RV_32A_UNDEF;
            endcase
        end else begin
            return RV_32A_UNDEF;
        end
    endcase
    
    typedef struct packed {
        bit DEVICE_INPUT; 
        bit DEVICE_OUTPUT; 
        bit MEM_READ;
        bit MEM_WRITE;
    } rv_fence_set;

endpackage

`endif

/*




Atomic Instructions:
    00010 aq rl 00000 rs1 010 rd 0101111 LR.W
    00011 aq rl rs2 rs1 010   rd 0101111 SC.W
    00001 aq rl rs2 rs1 010   rd 0101111 AMOSWAP.W
    00000 aq rl rs2 rs1 010   rd 0101111 AMOADD.W
    00100 aq rl rs2 rs1 010   rd 0101111 AMOXOR.W
    01100 aq rl rs2 rs1 010   rd 0101111 AMOAND.W
    01000 aq rl rs2 rs1 010   rd 0101111 AMOOR.W
    10000 aq rl rs2 rs1 010   rd 0101111 AMOMIN.W
    10100 aq rl rs2 rs1 010   rd 0101111 AMOMAX.W
    11000 aq rl rs2 rs1 010   rd 0101111 AMOMINU.W
    11100 aq rl rs2 rs1 010   rd 0101111 AMOMAXU.W

Integer Math Instructions:
    0000001 rs2 rs1 000 rd 0110011 MUL
    0000001 rs2 rs1 001 rd 0110011 MULH
    0000001 rs2 rs1 010 rd 0110011 MULHSU
    0000001 rs2 rs1 011 rd 0110011 MULHU
    0000001 rs2 rs1 100 rd 0110011 DIV
    0000001 rs2 rs1 101 rd 0110011 DIVU
    0000001 rs2 rs1 110 rd 0110011 REM
    0000001 rs2 rs1 111 rd 0110011 REMU

R-Type

    0000000 rs2 rs1 000 rd 0110011 ADD
    0100000 rs2 rs1 000 rd 0110011 SUB
    0000000 rs2 rs1 001 rd 0110011 SLL
    0000000 rs2 rs1 010 rd 0110011 SLT
    0000000 rs2 rs1 011 rd 0110011 SLTU
    0000000 rs2 rs1 100 rd 0110011 XOR
    0000000 rs2 rs1 101 rd 0110011 SRL
    0100000 rs2 rs1 101 rd 0110011 SRA
    0000000 rs2 rs1 110 rd 0110011 OR
    0000000 rs2 rs1 111 rd 0110011 AND

    0000 pred succ 00000 000 00000 0001111 FENCE
    0000 0000 0000 00000 001 00000 0001111 FENCE.I

    000000000000 00000 000 00000 1110011 ECALL
    000000000001 00000 000 00000 1110011 EBREAK
    csr rs1 001 rd 1110011 CSRRW
    csr rs1 010 rd 1110011 CSRRS
    csr rs1 011 rd 1110011 CSRRC
    csr zimm 101 rd 1110011 CSRRWI
    csr zimm 110 rd 1110011 CSRRSI
    csr zimm 111 rd 1110011 CSRRCI

U-Type

    imm[31:12] rd 0110111 LUI

    imm[31:12] rd 0010111 AUIPC

B-Type

    imm[12|10:5] rs2 rs1 000 imm[4:1|11] 1100011 BEQ
    imm[12|10:5] rs2 rs1 001 imm[4:1|11] 1100011 BNE
    imm[12|10:5] rs2 rs1 100 imm[4:1|11] 1100011 BLT
    imm[12|10:5] rs2 rs1 101 imm[4:1|11] 1100011 BGE
    imm[12|10:5] rs2 rs1 110 imm[4:1|11] 1100011 BLTU
    imm[12|10:5] rs2 rs1 111 imm[4:1|11] 1100011 BGEU

S-Type

    imm[11:5] rs2 rs1 000 imm[4:0] 0100011 SB
    imm[11:5] rs2 rs1 001 imm[4:0] 0100011 SH
    imm[11:5] rs2 rs1 010 imm[4:0] 0100011 SW

I-Type

    imm[11:0] rs1 000 rd 1100111 JALR

    imm[11:0] rs1 000 rd 0010011 ADDI
    imm[11:0] rs1 010 rd 0010011 SLTI
    imm[11:0] rs1 011 rd 0010011 SLTIU
    imm[11:0] rs1 100 rd 0010011 XORI
    imm[11:0] rs1 110 rd 0010011 ORI
    imm[11:0] rs1 111 rd 0010011 ANDI
    0000000 shamt rs1 001 rd 0010011 SLLI
    0000000 shamt rs1 101 rd 0010011 SRLI
    0100000 shamt rs1 101 rd 0010011 SRAI

    imm[11:0] rs1 000 rd 0000011 LB
    imm[11:0] rs1 001 rd 0000011 LH
    imm[11:0] rs1 010 rd 0000011 LW
    imm[11:0] rs1 100 rd 0000011 LBU
    imm[11:0] rs1 101 rd 0000011 LHU

J-Type

    imm[20|10:1|11|19:12] rd 1101111 JAL

Reid implemented 
    RV32IAS
    32I - Standard
    A - Atomic
    S - Supervisor (yet to read that doc)

Notes:
    RV_FENCE_I
        Forces executing processor to flush any existing memory operations before reading another instruction
    RV_FENCE


*/