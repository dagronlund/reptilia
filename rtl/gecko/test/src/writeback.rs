use rustdv::prelude::*;
use rustdv_utils::{
    convert::{LogicArrayDecode, LogicArrayEncode},
    expect_equal,
    reset::reset,
    stream::StreamPort,
};

use crate::types::GeckoOperation;

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
    let first = GeckoOperation {
        addr: 1,
        reg_status: 0,
        jump_flag: 0,
        value: 0x1111,
        mispredicted: false,
    };
    let second = GeckoOperation {
        addr: 2,
        reg_status: 0,
        jump_flag: 0,
        value: 0x2222,
        mispredicted: false,
    };
    input[0].payload.set_logic(&first.encode());
    input[1].payload.set_logic(&second.encode());
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
        expect_equal(GeckoOperation::decode(&output.payload)?, expected)?;
        input[index].valid.set_u64(0);
    }

    // Register 1 now expects status 1; stale status 0 must remain blocked.
    let stale = GeckoOperation {
        addr: 1,
        reg_status: 0,
        jump_flag: 0,
        value: 0x3333,
        mispredicted: false,
    };
    input[0].payload.set_logic(&stale.encode());
    input[0].valid.set_u64(1);
    for _ in 0..3 {
        clk.falling_edge().await;
        Timer::ns(4).await;
        if output.valid.is_high() {
            return Err(TestError::new("stale writeback status was accepted"));
        }
    }
    let next = GeckoOperation {
        addr: 1,
        reg_status: 1,
        jump_flag: 0,
        value: 0x3333,
        mispredicted: false,
    };
    input[0].payload.set_logic(&next.encode());
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
    expect_equal(GeckoOperation::decode(&output.payload)?, next)
}
