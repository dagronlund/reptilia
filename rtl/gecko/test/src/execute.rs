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
    let mut accepted = false;
    for _ in 0..20 {
        read_only().await;
        accepted |= command.valid.is_high() && command.ready.is_high();
        let received = result.valid.is_high() && result.ready.is_high();
        if received {
            let actual = u64::from(GeckoOperation::decode(&result.payload)?.value);
            expect_equal(actual, expected)?;
            expect_equal(accepted, true)?;
        }
        // The sampled handshakes occur at the intervening rising edge.
        // Withdraw the command on the next falling edge to send it only once.
        clk.falling_edge().await;
        command.valid.set_u64((!accepted) as u64);
        if received {
            return Ok(());
        }
    }
    Err(TestError::new("execute result timed out"))
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
    let mut accepted = false;
    let mut requested = false;
    for _ in 0..10 {
        read_only().await;
        accepted |= command.valid.is_high() && command.ready.is_high();
        requested = mem_request.valid.is_high();
        if requested {
            expect_equal(mem_request.addr.get_u64()?, 0x108)?;
            expect_equal(mem_request.data.get_u64()?, 0xdead_beef)?;
            expect_equal(mem_request.write_enable.get_u64()?, 0xf)?;
        }
        clk.falling_edge().await;
        command.valid.set_u64((!accepted) as u64);
        if requested && accepted {
            break;
        }
    }
    if !requested || !accepted {
        return Err(TestError::new("store request timed out"));
    }

    // A stalled store must complete before FENCE.I redirects even when the
    // predicted next PC already equals PC+4. It must not write a register.
    let fence = ExecuteOperation {
        op_type: 6,
        current_pc: 0x200,
        next_pc: 0x204,
        ..ExecuteOperation::default()
    };
    command.payload.set_logic_now(&fence.encode());
    command.valid.set_u64(1);
    for _ in 0..3 {
        read_only().await;
        expect_equal(command.ready.get_u64()?, 0)?;
        expect_equal(jump.valid.get_u64()?, 0)?;
        expect_equal(result.valid.get_u64()?, 0)?;
        clk.falling_edge().await;
    }
    mem_request.ready.set_u64(1);
    let mut accepted = false;
    for _ in 0..10 {
        read_only().await;
        accepted |= command.valid.is_high() && command.ready.is_high();
        let redirected = jump.valid.is_high() && jump.ready.is_high();
        if redirected {
            let actual = JumpOperation::decode(&jump.payload)?;
            expect_equal(actual.actual_next_pc as u64, 0x204)?;
            expect_equal(actual.update_pc as u64, 1)?;
            expect_equal(actual.mispredicted as u64, 0)?;
            expect_equal(result.valid.get_u64()?, 0)?;
            expect_equal(accepted, true)?;
        }
        clk.falling_edge().await;
        command.valid.set_u64((!accepted) as u64);
        if redirected {
            return Ok(());
        }
    }
    Err(TestError::new("FENCE.I redirect timed out"))
}
