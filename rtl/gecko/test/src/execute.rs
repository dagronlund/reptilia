use rustdv::prelude::*;
use rustdv_utils::{
    convert::{LogicArrayDecode, LogicArrayEncode},
    expect_equal,
    mem::MemPort,
    reset::reset,
    stream::StreamPort,
};

use crate::types::{ExecuteOperation, GeckoOperation, JumpOperation};

async fn send_alu(
    command: &StreamPort,
    result: &StreamPort,
    clk: &LogicHandle,
    operation: ExecuteOperation,
    expected: u64,
) -> Result<(), TestError> {
    command.payload.set_logic_now(&operation.encode());
    command.valid.set_u64(1);
    for _ in 0..20 {
        clk.falling_edge().await;
        Timer::ns(4).await;
        if result.valid.is_high() {
            break;
        }
    }
    if !result.valid.is_high() {
        return Err(TestError::new("execute result timed out"));
    }
    let actual = u64::from(GeckoOperation::decode(&result.payload)?.value);
    if actual != expected {
        return Err(TestError::new(format!(
            "ALU result: expected {expected:#x}, got {actual:#x}"
        )));
    }
    command.valid.set_u64(0);
    clk.falling_edge().await;
    Ok(())
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn gecko_execute(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let command = StreamPort::new(&dut, "execute_command")?;
    let mem_command = StreamPort::new(&dut, "mem_command")?;
    let mem_request = MemPort::new(&dut, "mem_request")?;
    let result = StreamPort::new(&dut, "execute_result")?;
    let jump = StreamPort::new(&dut, "jump_command")?;

    command.valid.set_u64(0);
    command
        .payload
        .set_logic_now(&ExecuteOperation::default().encode());
    dut.signal("instruction_updated")?.set_u64(0);
    mem_command.ready.set_u64(0);
    mem_request.ready.set_u64(0);
    result.ready.set_u64(0);
    jump.ready.set_u64(0);
    let clk = reset(&dut).await?;
    result.ready.set_u64(1);
    jump.ready.set_u64(1);
    mem_command.ready.set_u64(1);
    mem_request.ready.set_u64(1);

    send_alu(
        &command,
        &result,
        &clk,
        ExecuteOperation {
            rs1_value: 10,
            rs2_value: 7,
            reg_addr: 3,
            ..ExecuteOperation::default()
        },
        17,
    )
    .await?;
    send_alu(
        &command,
        &result,
        &clk,
        ExecuteOperation {
            alternate: true,
            rs1_value: 10,
            rs2_value: 7,
            reg_addr: 3,
            ..ExecuteOperation::default()
        },
        3,
    )
    .await?;
    send_alu(
        &command,
        &result,
        &clk,
        ExecuteOperation {
            op: 4,
            rs1_value: 0xaa55,
            rs2_value: 0x0f0f,
            reg_addr: 3,
            ..ExecuteOperation::default()
        },
        0xa55a,
    )
    .await?;

    // Store word: address = rs1 + rs2, data = mem_value.
    mem_request.ready.set_u64(0);
    let store = ExecuteOperation {
        reg_addr: 3,
        op_type: 2,
        op: 2,
        rs1_value: 0x100,
        rs2_value: 8,
        mem_value: 0xdead_beef,
        ..ExecuteOperation::default()
    };
    command.payload.set_logic_now(&store.encode());
    command.valid.set_u64(1);
    for _ in 0..10 {
        clk.falling_edge().await;
        Timer::ns(4).await;
        if mem_request.valid.is_high() {
            break;
        }
    }
    if !mem_request.valid.is_high() {
        return Err(TestError::new("store request timed out"));
    }
    expect_equal(mem_request.addr.get_u64()?, 0x108)?;
    expect_equal(mem_request.data.get_u64()?, 0xdead_beef)?;
    expect_equal(mem_request.write_enable.get_u64()?, 0xf)?;

    // A stalled store must complete before FENCE.I redirects even when the
    // predicted next PC already equals PC+4. It must not write a register.
    let fence = ExecuteOperation {
        op_type: 6,
        current_pc: 0x200,
        next_pc: 0x204,
        ..ExecuteOperation::default()
    };
    command.payload.set_logic_now(&fence.encode());
    for _ in 0..3 {
        clk.falling_edge().await;
        Timer::ns(4).await;
        expect_equal(command.ready.get_u64()?, 0)?;
        expect_equal(jump.valid.get_u64()?, 0)?;
        expect_equal(result.valid.get_u64()?, 0)?;
    }
    mem_request.ready.set_u64(1);
    for _ in 0..10 {
        clk.falling_edge().await;
        Timer::ns(4).await;
        if jump.valid.is_high() {
            let actual = JumpOperation::decode(&jump.payload)?;
            expect_equal(actual.actual_next_pc as u64, 0x204)?;
            expect_equal(actual.update_pc as u64, 1)?;
            expect_equal(actual.mispredicted as u64, 0)?;
            expect_equal(result.valid.get_u64()?, 0)?;
            command.valid.set_u64(0);
            return Ok(());
        }
    }
    Err(TestError::new("FENCE.I redirect timed out"))
}
