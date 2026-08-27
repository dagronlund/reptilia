use rustdv::prelude::*;

use crate::{MemInputPort, MemOutputPort, MemTransaction, start, transact};

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn mem_sequential_read_write(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    // Separate write/read channels: fill, then update one bank while reading another.
    let wv = dut
        .signal("mem_write_in.valid")
        .map_err(|e| TestError::new(e.to_string()))?;
    let wr = dut
        .signal("mem_write_in.ready")
        .map_err(|e| TestError::new(e.to_string()))?;
    let wa = dut
        .signal("mem_write_in.addr")
        .map_err(|e| TestError::new(e.to_string()))?;
    let wd = dut
        .signal("mem_write_in.data")
        .map_err(|e| TestError::new(e.to_string()))?;
    let rp = (
        MemInputPort::new(&dut, "mem_read_in").map_err(|e| TestError::new(e.to_string()))?,
        MemOutputPort::new(&dut, "mem_read_out").map_err(|e| TestError::new(e.to_string()))?,
    );
    wv.set_u64(0);
    let clk = start(&dut, &[rp]).await?;
    let mut rng = ctx.rng();
    for i in 0..128u16 {
        clk.falling_edge().await;
        wv.set_u64(1);
        wa.set_u64(i as u64);
        wd.set_u64((0x3000 + i as u32) as u64);
        clk.rising_edge().await;
        read_only().await;
        if !wr.is_high() {
            return Err(TestError::new("write port not ready"));
        }
    }
    clk.falling_edge().await;
    wv.set_u64(0);
    for i in 0..64u16 {
        // Write the upper bank while reading the already initialized lower bank.
        clk.falling_edge().await;
        wv.set_u64(1);
        wa.set_u64((64 + i) as u64);
        wd.set_u64((0x4000 + i as u32) as u64);
        clk.rising_edge().await;
        read_only().await;
        transact(
            &clk,
            &rp.0,
            &rp.1,
            MemTransaction {
                read: true,
                write: 0,
                addr: i,
                data: 0,
                id: (i & 15) as u8,
                last: i == 63,
            },
            Some((0x3000 + i as u32, (i & 15) as u8, i == 63)),
            &mut rng,
        )
        .await?;
    }
    Ok(())
}
