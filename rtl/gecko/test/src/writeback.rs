use rustdv::prelude::*;

use crate::{StreamPort, reset};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct GeckoOperation {
    pub(crate) addr: u8,
    pub(crate) reg_status: u8,
    pub(crate) jump_flag: u8,
    pub(crate) value: u32,
    pub(crate) mispredicted: bool,
}

impl GeckoOperation {
    fn new(addr: u8, reg_status: u8, value: u32) -> Self {
        Self {
            addr,
            reg_status,
            jump_flag: 0,
            value,
            mispredicted: false,
        }
    }

    pub(crate) fn encode(self) -> u64 {
        (u64::from(self.addr & 0x1f) << 38)
            | (u64::from(self.reg_status & 0x7) << 35)
            | (u64::from(self.jump_flag & 0x3) << 33)
            | (u64::from(self.value) << 1)
            | u64::from(self.mispredicted)
    }

    pub(crate) fn decode(payload: u64) -> Self {
        Self {
            addr: ((payload >> 38) & 0x1f) as u8,
            reg_status: ((payload >> 35) & 0x7) as u8,
            jump_flag: ((payload >> 33) & 0x3) as u8,
            value: ((payload >> 1) & 0xffff_ffff) as u32,
            mispredicted: payload & 1 != 0,
        }
    }
}

fn read_operation(port: &StreamPort) -> Result<GeckoOperation, TestError> {
    let payload = port
        .payload
        .get_u64()
        .map_err(|error| TestError::new(error.to_string()))?;
    Ok(GeckoOperation::decode(payload))
}

fn expect_operation(port: &StreamPort, expected: GeckoOperation) -> Result<(), TestError> {
    let actual = read_operation(port)?;
    if actual != expected {
        return Err(TestError::new(format!(
            "writeback operation: expected {expected:?}, got {actual:?}"
        )));
    }
    Ok(())
}

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn gecko_writeback(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let input = [
        StreamPort::new(&dut, "writeback_results_in[0]")?,
        StreamPort::new(&dut, "writeback_results_in[1]")?,
    ];
    let output = StreamPort::new(&dut, "writeback_result")?;
    for port in &input {
        port.valid.set_u64(0);
        port.payload.set_u64(0);
    }
    output.ready.set_u64(0);
    let clk = reset(&dut).await?;
    output.ready.set_u64(1);

    // AUTO_RESET clears one register-status entry per cycle.
    for _ in 0..40 {
        clk.falling_edge().await;
    }
    let first = GeckoOperation::new(1, 0, 0x1111);
    let second = GeckoOperation::new(2, 0, 0x2222);
    input[0].payload.set_u64(first.encode());
    input[1].payload.set_u64(second.encode());
    input[0].valid.set_u64(1);
    input[1].valid.set_u64(1);

    for (index, expected) in [first, second].into_iter().enumerate() {
        for _ in 0..10 {
            clk.falling_edge().await;
            Timer::ns(4).await;
            if output.valid.is_high() {
                break;
            }
        }
        if !output.valid.is_high() {
            return Err(TestError::new("writeback arbitration timed out"));
        }
        expect_operation(&output, expected)?;
        input[index].valid.set_u64(0);
    }

    // Register 1 now expects status 1; stale status 0 must remain blocked.
    let stale = GeckoOperation::new(1, 0, 0x3333);
    input[0].payload.set_u64(stale.encode());
    input[0].valid.set_u64(1);
    for _ in 0..3 {
        clk.falling_edge().await;
        Timer::ns(4).await;
        if output.valid.is_high() {
            return Err(TestError::new("stale writeback status was accepted"));
        }
    }
    let next = GeckoOperation::new(1, 1, 0x3333);
    input[0].payload.set_u64(next.encode());
    for _ in 0..10 {
        clk.falling_edge().await;
        Timer::ns(4).await;
        if output.valid.is_high() {
            break;
        }
    }
    if !output.valid.is_high() {
        return Err(TestError::new("next-status writeback timed out"));
    }
    expect_operation(&output, next)
}
