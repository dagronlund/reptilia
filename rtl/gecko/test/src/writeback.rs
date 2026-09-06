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

    let mut accepted = [false; 2];
    let mut received = 0;
    for _ in 0..10 {
        read_only().await;
        for (index, port) in (&input).into_iter().enumerate() {
            accepted[index] |= port.valid.is_high() && port.ready.is_high();
        }
        if output.valid.is_high() && output.ready.is_high() {
            let expected = [first, second]
                .get(received)
                .copied()
                .ok_or_else(|| TestError::new("unexpected extra writeback"))?;
            expect_equal(GeckoOperation::decode(&output.payload)?, expected)?;
            received += 1;
        }
        // Retire each input after its own handshake, independently of the
        // registered output, so neither input is submitted twice.
        clk.falling_edge().await;
        for (index, port) in (&input).into_iter().enumerate() {
            port.valid.set_u64((!accepted[index]) as u64);
        }
        if received == 2 {
            break;
        }
    }
    if received != 2 || accepted != [true, true] {
        return Err(TestError::new("writeback arbitration timed out"));
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
        read_only().await;
        expect_equal(input[0].ready.get_u64()?, 0)?;
        if output.valid.is_high() {
            return Err(TestError::new("stale writeback status was accepted"));
        }
        clk.falling_edge().await;
    }
    let next = GeckoOperation {
        addr: 1,
        reg_status: 1,
        jump_flag: 0,
        value: 0x3333,
        mispredicted: false,
    };
    input[0].payload.set_logic(&next.encode());
    let mut accepted = false;
    for _ in 0..10 {
        read_only().await;
        accepted |= input[0].valid.is_high() && input[0].ready.is_high();
        let received = output.valid.is_high() && output.ready.is_high();
        if received {
            expect_equal(GeckoOperation::decode(&output.payload)?, next)?;
            expect_equal(accepted, true)?;
        }
        clk.falling_edge().await;
        input[0].valid.set_u64((!accepted) as u64);
        if received {
            return Ok(());
        }
    }
    Err(TestError::new("next-status writeback timed out"))
}
