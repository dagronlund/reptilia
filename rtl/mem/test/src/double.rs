use rustdv::prelude::*;

use crate::{MemPort, MemTxn, fail, start, transact};

#[rustdv::test(timeout_time = 5, timeout_unit = "ms")]
async fn mem_sequential_double(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    // Exercise both registered dual-port channels and cross-port visibility.
    let p0 = MemPort::new(&dut, "d0", "d0o").map_err(|e| fail(e.to_string()))?;
    let p1 = MemPort::new(&dut, "d1", "d1o").map_err(|e| fail(e.to_string()))?;
    let clk = start(&dut, &[p0, p1]).await?;
    let mut rng = ctx.rng();
    for i in 0..64u16 {
        // Both requests are held over the same cycle, providing genuine concurrent traffic.
        clk.falling_edge().await;
        let a = MemTxn {
            read: false,
            write: 15,
            addr: i,
            data: 0x1000 + i as u32,
            id: (i & 15) as u8,
            last: i == 63,
        };
        let b = MemTxn {
            read: false,
            write: 15,
            addr: 64 + i,
            data: 0x2000 + i as u32,
            id: (i & 15) as u8,
            last: i == 63,
        };
        p0.drive(a);
        p1.drive(b);
        p0.valid.set_u64(1);
        p1.valid.set_u64(1);
        p0.out_ready.set_u64(1);
        p1.out_ready.set_u64(1);
        // Observe the settled combinational handshake immediately before the
        // active edge. Sampling after the edge can see the next selected input.
        Timer::ns(4).await;
        if !p0.ready.is_high() || !p1.ready.is_high() {
            return Err(fail("dual-port write stalled unexpectedly"));
        }
        clk.falling_edge().await;
        p0.valid.set_u64(0);
        p1.valid.set_u64(0);
    }
    for i in 0..64u16 {
        transact(
            &clk,
            &p0,
            MemTxn {
                read: true,
                write: 0,
                addr: 64 + i,
                data: 0,
                id: (i & 15) as u8,
                last: i == 63,
            },
            Some((0x2000 + i as u32, (i & 15) as u8, i == 63)),
            &mut rng,
        )
        .await?;
        transact(
            &clk,
            &p1,
            MemTxn {
                read: true,
                write: 0,
                addr: i,
                data: 0,
                id: (i & 15) as u8,
                last: i == 63,
            },
            Some((0x1000 + i as u32, (i & 15) as u8, i == 63)),
            &mut rng,
        )
        .await?;
    }
    Ok(())
}
