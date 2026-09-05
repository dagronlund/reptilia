use num_bigint::BigUint;
use rustdv_utils::convert::LogicArrayEncode;

use crate::types::{ExecuteOperation, GeckoOperation, InstructionOperation, JumpOperation};

#[test]
fn gecko_operation_encoding_round_trips() {
    let operation = GeckoOperation {
        addr: 0x1b,
        reg_status: 5,
        jump_flag: 2,
        value: 0xdead_beef,
        mispredicted: true,
    };
    let encoded = operation.encode();
    assert_eq!(encoded.len(), 43);
    let payload = u64::try_from(&encoded).unwrap();
    assert_eq!(
        payload,
        (0x1b_u64 << 38) | (5 << 35) | (2 << 33) | (0xdead_beef << 1) | 1
    );
    assert_eq!(GeckoOperation::from(payload), operation);
}

#[test]
fn execute_operation_matches_rtl_layout() {
    let operation = ExecuteOperation {
        prediction_history: 3,
        immediate_value: 1 << 31,
        jump_value: 1,
        rs1_value: 1 << 31,
        reuse_jump: true,
        reg_addr: 0x1f,
        ..ExecuteOperation::default()
    };
    let encoded = operation.encode();
    let expected = BigUint::from(3_u8)
        | (BigUint::from(1_u8) << 98)
        | (BigUint::from(1_u8) << 99)
        | (BigUint::from(1_u8) << 226)
        | (BigUint::from(1_u8) << 227)
        | (BigUint::from(0x1f_u8) << 245);
    assert_eq!(encoded.len(), 250);
    assert_eq!(BigUint::try_from(&encoded), Ok(expected));
}

#[test]
fn jump_operation_has_rtl_width() {
    assert_eq!(JumpOperation::default().encode().len(), 72);
}

#[test]
fn instruction_operation_has_rtl_width() {
    let operation = InstructionOperation {
        pc: 0x1234_5678,
        next_pc: 0x9abc_def0,
        prediction_miss: true,
        prediction_history: 3,
        pc_updated: true,
    };
    let encoded = operation.encode();
    let expected = (0x1234_5678_u128 << 36) | (0x9abc_def0 << 4) | (1 << 3) | (3 << 1) | 1;
    assert_eq!(encoded.len(), 68);
    assert_eq!(u128::try_from(&encoded), Ok(expected));
}
