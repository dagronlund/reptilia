use rustdv::prelude::*;
use rustdv_utils::{mem::MemPort, stream::StreamPort};

use crate::{expect, pack_fields, packed_bits, reset, signal};

#[derive(Clone, Copy, Default)]
pub(crate) struct ExecuteOperation {
    reg_addr: u8,
    reg_status: u8,
    jump_flag: u8,
    pc_updated: bool,
    halt: bool,
    op_type: u8,
    op: u8,
    alternate: bool,
    reuse_rs1: bool,
    reuse_rs2: bool,
    reuse_mem: bool,
    reuse_jump: bool,
    rs1_value: u32,
    rs2_value: u32,
    mem_value: u32,
    jump_value: u32,
    immediate_value: u32,
    current_pc: u32,
    next_pc: u32,
    prediction_miss: bool,
    prediction_history: u8,
}

impl ExecuteOperation {
    pub(crate) fn encode(self) -> LogicArray {
        pack_fields(&[
            (u64::from(self.reg_addr), 5),
            (u64::from(self.reg_status), 3),
            (u64::from(self.jump_flag), 2),
            (self.pc_updated as u64, 1),
            (self.halt as u64, 1),
            (u64::from(self.op_type), 3),
            (u64::from(self.op), 3),
            (self.alternate as u64, 1),
            (self.reuse_rs1 as u64, 1),
            (self.reuse_rs2 as u64, 1),
            (self.reuse_mem as u64, 1),
            (self.reuse_jump as u64, 1),
            (u64::from(self.rs1_value), 32),
            (u64::from(self.rs2_value), 32),
            (u64::from(self.mem_value), 32),
            (u64::from(self.jump_value), 32),
            (u64::from(self.immediate_value), 32),
            (u64::from(self.current_pc), 32),
            (u64::from(self.next_pc), 32),
            (self.prediction_miss as u64, 1),
            (u64::from(self.prediction_history), 2),
        ])
    }
}

fn result_value(result: &StreamPort) -> Result<u64, TestError> {
    let payload = result
        .payload
        .get_logic()
        .map_err(|error| TestError::new(error.to_string()))?;
    packed_bits(&payload, 1, 32)
}

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
    let actual = result_value(result)?;
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
    let command = StreamPort::new(&dut, "execute_command")
        .map_err(|error| TestError::new(error.to_string()))?;
    let mem_command =
        StreamPort::new(&dut, "mem_command").map_err(|error| TestError::new(error.to_string()))?;
    let mem_request =
        MemPort::new(&dut, "mem_request").map_err(|error| TestError::new(error.to_string()))?;
    let result = StreamPort::new(&dut, "execute_result")
        .map_err(|error| TestError::new(error.to_string()))?;
    let jump =
        StreamPort::new(&dut, "jump_command").map_err(|error| TestError::new(error.to_string()))?;

    command.valid.set_u64(0);
    command
        .payload
        .set_logic_now(&ExecuteOperation::default().encode());
    signal(&dut, "instruction_updated")?.set_u64(0);
    mem_command.ready.set_u64(0);
    mem_request.ready.set_u64(0);
    result.ready.set_u64(0);
    jump.ready.set_u64(0);
    let clk = reset(&dut).await?;
    result.ready.set_u64(1);
    jump.ready.set_u64(1);
    mem_command.ready.set_u64(1);
    mem_request.ready.set_u64(1);

    let base = ExecuteOperation {
        reg_addr: 3,
        ..ExecuteOperation::default()
    };
    send_alu(
        &command,
        &result,
        &clk,
        ExecuteOperation {
            rs1_value: 10,
            rs2_value: 7,
            ..base
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
            ..base
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
            ..base
        },
        0xa55a,
    )
    .await?;

    // Store word: address = rs1 + rs2, data = mem_value.
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
    expect(&mem_request.addr, 0x108, "store address")?;
    expect(&mem_request.data, 0xdead_beef, "store data")?;
    expect(&mem_request.write_enable, 0xf, "store mask")
}
