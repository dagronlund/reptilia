use rustdv::prelude::*;
use rustdv_utils::{
    convert::{LogicArrayDecode, LogicArrayEncode},
    expect_equal,
    mem::MemPort,
    reset::reset,
    stream::StreamPort,
};

use crate::types::{ExecuteOperation, InstructionOperation};

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn gecko_decode(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let instruction_result = MemPort::new(&dut, "instruction_result")?;
    let instruction_command = StreamPort::new(&dut, "instruction_command")?;
    let system_command = StreamPort::new(&dut, "system_command")?;
    let execute_command = StreamPort::new(&dut, "execute_command")?;
    let float_command = StreamPort::new(&dut, "float_command")?;
    let jump_command = StreamPort::new(&dut, "jump_command")?;
    let writeback_result = StreamPort::new(&dut, "writeback_result")?;

    instruction_result.valid.set_u64(0);
    instruction_result.read_enable.set_u64(0);
    instruction_result.write_enable.set_u64(0);
    instruction_result.addr.set_u64(0);
    instruction_result.data.set_u64(0);
    dut.signal("instruction_result.id")?.set_u64(0);
    dut.signal("instruction_result.last")?.set_u64(0);
    instruction_command.valid.set_u64(0);
    instruction_command
        .payload
        .set_logic_now(&LogicArray::from_u64(0, 68));
    jump_command.valid.set_u64(0);
    jump_command
        .payload
        .set_logic_now(&LogicArray::from_u64(0, 72));
    writeback_result.valid.set_u64(0);
    writeback_result.payload.set_u64(0);
    system_command.ready.set_u64(0);
    execute_command.ready.set_u64(0);
    float_command.ready.set_u64(0);
    let clk = reset(&dut).await?;
    execute_command.ready.set_u64(1);

    // ADDI x1, x0, 42
    instruction_result.data.set_u64(0x02a0_0093);
    instruction_result.read_enable.set_u64(1);
    let operation = InstructionOperation {
        pc: 0x100,
        next_pc: 0x104,
        prediction_miss: false,
        prediction_history: 0,
        pc_updated: false,
    };
    instruction_command
        .payload
        .set_logic_now(&operation.encode());
    instruction_result.valid.set_u64(1);
    instruction_command.valid.set_u64(1);

    for _ in 0..100 {
        clk.falling_edge().await;
        read_only().await;
        if execute_command.valid.is_high() {
            break;
        }
    }
    if !execute_command.valid.is_high() {
        return Err(TestError::new("decode did not emit ADDI"));
    }
    let actual = ExecuteOperation::decode(&execute_command.payload)?;
    let expected = ExecuteOperation {
        reg_addr: 1,
        reg_status: 0,
        op_type: 0,
        op: 0,
        rs1_value: 0,
        rs2_value: 42,
        immediate_value: 42,
        jump_value: 0x100,
        current_pc: 0x100,
        next_pc: 0x104,
        ..ExecuteOperation::default()
    };
    if actual != expected {
        return Err(TestError::new(format!(
            "decoded ADDI: expected {expected:?}, got {actual:?}"
        )));
    }
    expect_equal(dut.signal("error_flag")?.get_u64()?, 0)
}
