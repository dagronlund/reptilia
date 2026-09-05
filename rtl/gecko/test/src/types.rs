use indiscriminant::indiscriminant;

#[indiscriminant(u64, From)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct GeckoOperation {
    pub(crate) mispredicted: bool,
    pub(crate) value: u32,
    #[width(2)]
    pub(crate) jump_flag: u8,
    #[width(3)]
    pub(crate) reg_status: u8,
    #[width(5)]
    pub(crate) addr: u8,
}

#[indiscriminant(u128, From)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct InstructionOperation {
    pub(crate) pc_updated: bool,
    #[width(2)]
    pub(crate) prediction_history: u8,
    pub(crate) prediction_miss: bool,
    pub(crate) next_pc: u32,
    pub(crate) pc: u32,
}

#[indiscriminant(u128, From)]
#[derive(Clone, Copy, Default)]
pub(crate) struct JumpOperation {
    pub(crate) mispredicted: bool,
    pub(crate) halt: bool,
    #[width(2)]
    pub(crate) prediction_history: u8,
    pub(crate) prediction_miss: bool,
    pub(crate) actual_next_pc: u32,
    pub(crate) current_pc: u32,
    pub(crate) jumped: bool,
    pub(crate) branched: bool,
    pub(crate) update_pc: bool,
}

#[indiscriminant(BigUint, From)]
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub(crate) struct ExecuteOperation {
    #[width(2)]
    pub(crate) prediction_history: u8,
    pub(crate) prediction_miss: bool,
    pub(crate) next_pc: u32,
    pub(crate) current_pc: u32,
    pub(crate) immediate_value: u32,
    pub(crate) jump_value: u32,
    pub(crate) mem_value: u32,
    pub(crate) rs2_value: u32,
    pub(crate) rs1_value: u32,
    pub(crate) reuse_jump: bool,
    pub(crate) reuse_mem: bool,
    pub(crate) reuse_rs2: bool,
    pub(crate) reuse_rs1: bool,
    pub(crate) alternate: bool,
    #[width(3)]
    pub(crate) op: u8,
    #[width(3)]
    pub(crate) op_type: u8,
    pub(crate) halt: bool,
    pub(crate) pc_updated: bool,
    #[width(2)]
    pub(crate) jump_flag: u8,
    #[width(3)]
    pub(crate) reg_status: u8,
    #[width(5)]
    pub(crate) reg_addr: u8,
}
