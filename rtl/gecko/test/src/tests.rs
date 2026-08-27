use crate::decode::InstructionOperation;
use crate::execute::ExecuteOperation;
use crate::fetch::JumpOperation;
use crate::writeback::GeckoOperation;

#[test]
fn gecko_operation_encoding_round_trips() {
    let operation = GeckoOperation {
        addr: 0x1b,
        reg_status: 5,
        jump_flag: 2,
        value: 0xdead_beef,
        mispredicted: true,
    };
    assert_eq!(GeckoOperation::decode(operation.encode()), operation);
}

#[test]
fn execute_operation_has_rtl_width() {
    assert_eq!(ExecuteOperation::default().encode().len(), 250);
}

#[test]
fn jump_operation_has_rtl_width() {
    assert_eq!(JumpOperation::default().encode().len(), 72);
}

#[test]
fn instruction_operation_has_rtl_width() {
    let operation = InstructionOperation {
        pc: 0,
        next_pc: 4,
        prediction_miss: false,
        prediction_history: 0,
        pc_updated: false,
    };
    assert_eq!(operation.encode().len(), 68);
}
