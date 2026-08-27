use rustdv::prelude::*;
use rustdv_utils::{mem::MemPort, stream::StreamPort};

use crate::{expect, packed_bits, reset, set_packed, signal};

#[derive(Clone, Copy)]
pub(crate) struct InstructionOperation {
    pub(crate) pc: u32,
    pub(crate) next_pc: u32,
    pub(crate) prediction_miss: bool,
    pub(crate) prediction_history: u8,
    pub(crate) pc_updated: bool,
}

impl InstructionOperation {
    pub(crate) fn encode(self) -> String {
        format!(
            "{:032b}{:032b}{:01b}{:02b}{:01b}",
            self.pc,
            self.next_pc,
            self.prediction_miss as u8,
            self.prediction_history & 0x3,
            self.pc_updated as u8,
        )
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct ExecuteOperation {
    reg_addr: u8,
    reg_status: u8,
    op_type: u8,
    op: u8,
    rs1_value: u32,
    rs2_value: u32,
    current_pc: u32,
    next_pc: u32,
}

impl ExecuteOperation {
    fn decode(payload: &LogicHandle) -> Result<Self, TestError> {
        Ok(Self {
            reg_addr: packed_bits(payload, 245, 5)? as u8,
            reg_status: packed_bits(payload, 242, 3)? as u8,
            op_type: packed_bits(payload, 235, 3)? as u8,
            op: packed_bits(payload, 232, 3)? as u8,
            rs1_value: packed_bits(payload, 195, 32)? as u32,
            rs2_value: packed_bits(payload, 163, 32)? as u32,
            current_pc: packed_bits(payload, 35, 32)? as u32,
            next_pc: packed_bits(payload, 3, 32)? as u32,
        })
    }
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn gecko_decode(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let instruction_result = MemPort::new(&dut, "instruction_result")
        .map_err(|error| TestError::new(error.to_string()))?;
    let instruction_command = StreamPort::new(&dut, "instruction_command")
        .map_err(|error| TestError::new(error.to_string()))?;
    let system_command = StreamPort::new(&dut, "system_command")
        .map_err(|error| TestError::new(error.to_string()))?;
    let execute_command = StreamPort::new(&dut, "execute_command")
        .map_err(|error| TestError::new(error.to_string()))?;
    let float_command = StreamPort::new(&dut, "float_command")
        .map_err(|error| TestError::new(error.to_string()))?;
    let jump_command =
        StreamPort::new(&dut, "jump_command").map_err(|error| TestError::new(error.to_string()))?;
    let writeback_result = StreamPort::new(&dut, "writeback_result")
        .map_err(|error| TestError::new(error.to_string()))?;

    instruction_result.valid.set_u64(0);
    instruction_result.read_enable.set_u64(0);
    instruction_result.write_enable.set_u64(0);
    instruction_result.addr.set_u64(0);
    instruction_result.data.set_u64(0);
    signal(&dut, "instruction_result.id")?.set_u64(0);
    signal(&dut, "instruction_result.last")?.set_u64(0);
    instruction_command.valid.set_u64(0);
    set_packed(&instruction_command.payload, &"0".repeat(68));
    jump_command.valid.set_u64(0);
    set_packed(&jump_command.payload, &"0".repeat(72));
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
    set_packed(&instruction_command.payload, &operation.encode());
    instruction_result.valid.set_u64(1);
    instruction_command.valid.set_u64(1);

    for _ in 0..100 {
        clk.falling_edge().await;
        Timer::ns(4).await;
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
        current_pc: 0x100,
        next_pc: 0x104,
    };
    if actual != expected {
        return Err(TestError::new(format!(
            "decoded ADDI: expected {expected:?}, got {actual:?}"
        )));
    }
    expect(
        &signal(&dut, "error_flag")?,
        0,
        "valid instruction error flag",
    )
}
