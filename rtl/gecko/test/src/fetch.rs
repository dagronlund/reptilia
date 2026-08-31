use rustdv::prelude::*;
use rustdv_utils::{mem::MemPort, stream::StreamPort};

use crate::{expect, pack_fields, packed_bits, reset};

#[derive(Clone, Copy, Default)]
pub(crate) struct JumpOperation {
    update_pc: bool,
    branched: bool,
    jumped: bool,
    current_pc: u32,
    actual_next_pc: u32,
    prediction_miss: bool,
    prediction_history: u8,
    halt: bool,
    mispredicted: bool,
}

impl JumpOperation {
    pub(crate) fn encode(self) -> LogicArray {
        pack_fields(&[
            (self.update_pc as u64, 1),
            (self.branched as u64, 1),
            (self.jumped as u64, 1),
            (u64::from(self.current_pc), 32),
            (u64::from(self.actual_next_pc), 32),
            (self.prediction_miss as u64, 1),
            (u64::from(self.prediction_history), 2),
            (self.halt as u64, 1),
            (self.mispredicted as u64, 1),
        ])
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct InstructionOperation {
    pc: u32,
    next_pc: u32,
    pc_updated: bool,
}

impl InstructionOperation {
    fn decode(payload: &LogicHandle) -> Result<Self, TestError> {
        let payload = payload
            .get_logic()
            .map_err(|error| TestError::new(error.to_string()))?;
        Ok(Self {
            pc: packed_bits(&payload, 36, 32)? as u32,
            next_pc: packed_bits(&payload, 4, 32)? as u32,
            pc_updated: packed_bits(&payload, 0, 1)? != 0,
        })
    }
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn gecko_fetch(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let jump =
        StreamPort::new(&dut, "jump_command").map_err(|error| TestError::new(error.to_string()))?;
    let instruction = StreamPort::new(&dut, "instruction_command")
        .map_err(|error| TestError::new(error.to_string()))?;
    let request = MemPort::new(&dut, "instruction_request")
        .map_err(|error| TestError::new(error.to_string()))?;
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
        };
        if actual != expected {
            return Err(TestError::new(format!(
                "instruction operation: expected {expected:?}, got {actual:?}"
            )));
        }
        expect(
            &request.addr,
            u64::from(expected_pc),
            "instruction request address",
        )?;
        expect(&request.read_enable, 1, "instruction request read enable")?;
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
        })
    {
        return Err(TestError::new(format!(
            "redirected instruction mismatch: {redirected:?}"
        )));
    }
    expect(&request.addr, 0x40, "redirected request address")?;

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
    expect(&instruction.valid, 0, "halted instruction stream")?;
    expect(&request.valid, 0, "halted request stream")
}
