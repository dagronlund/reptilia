use rustdv::prelude::*;
use rustdv_utils::{
    convert::{LogicArrayDecode, LogicArrayEncode},
    expect_equal,
    mem::MemPort,
    reset::reset,
    stream::StreamPort,
};

use crate::types::{InstructionOperation, JumpOperation};

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn gecko_fetch(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let jump = StreamPort::new(&dut, "jump_command")?;
    let instruction = StreamPort::new(&dut, "instruction_command")?;
    let request = MemPort::new(&dut, "instruction_request")?;
    jump.valid.set_u64(0);
    jump.payload
        .set_logic_now(&JumpOperation::default().encode());
    instruction.ready.set_u64(0);
    request.ready.set_u64(0);
    let clk = reset(&dut).await?;

    instruction.ready.set_u64(1);
    request.ready.set_u64(1);
    for expected_pc in [0u32, 4, 8] {
        for _ in 0..80 {
            Timer::ns(4).await;
            if instruction.valid.is_high() && request.valid.is_high() {
                break;
            }
            clk.falling_edge().await;
        }
        if !instruction.valid.is_high() || !request.valid.is_high() {
            return Err(TestError::new("fetch did not produce an instruction pair"));
        }
        let actual = InstructionOperation::decode(&instruction.payload)?;
        let expected = InstructionOperation {
            pc: expected_pc,
            next_pc: expected_pc + 4,
            pc_updated: false,
            prediction_history: 0,
            prediction_miss: true,
        };
        if actual != expected {
            return Err(TestError::new(format!(
                "instruction operation: expected {expected:?}, got {actual:?}"
            )));
        }
        expect_equal(request.addr.get_u64()?, u64::from(expected_pc))?;
        expect_equal(request.read_enable.get_u64()?, 1)?;
        clk.falling_edge().await;
    }

    let redirect = JumpOperation {
        update_pc: true,
        actual_next_pc: 0x40,
        ..JumpOperation::default()
    };
    jump.payload.set_logic_now(&redirect.encode());
    jump.valid.set_u64(1);
    clk.falling_edge().await;
    jump.valid.set_u64(0);
    Timer::ns(4).await;
    let redirected = InstructionOperation::decode(&instruction.payload)?;
    if redirected
        != (InstructionOperation {
            pc: 0x40,
            next_pc: 0x44,
            pc_updated: true,
            prediction_history: 1,
            prediction_miss: true,
        })
    {
        return Err(TestError::new(format!(
            "redirected instruction mismatch: {redirected:?}"
        )));
    }
    expect_equal(request.addr.get_u64()?, 0x40)?;

    let halt = JumpOperation {
        halt: true,
        ..JumpOperation::default()
    };
    jump.payload.set_logic_now(&halt.encode());
    jump.valid.set_u64(1);
    clk.falling_edge().await;
    jump.valid.set_u64(0);
    clk.falling_edge().await;
    Timer::ns(4).await;
    expect_equal(instruction.valid.get_u64()?, 0)?;
    expect_equal(request.valid.get_u64()?, 0)
}
