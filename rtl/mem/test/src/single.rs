use rustdv::prelude::*;
use rustdv_utils::mem::{MemPort, MemTransaction};

use crate::{start, transact};

#[rustdv::test(timeout_time = 30, timeout_unit = "ms")]
async fn mem_sequential_single(ctx: RustdvCtx) -> Result<(), TestError> {
    let dut = ctx.dut();
    let p = (
        MemPort::new(&dut, "mem_in").map_err(|e| TestError::new(e.to_string()))?,
        MemPort::new(&dut, "mem_out").map_err(|e| TestError::new(e.to_string()))?,
    );
    let clk = start(&dut, &[p]).await?;
    let mut rng = ctx.rng();
    for i in 0..1024u16 {
        transact(
            &clk,
            &p.0,
            &p.1,
            MemTransaction {
                read: false,
                write: 15,
                addr: i,
                data: 1023 - i as u32,
                id: (i & 15) as u8,
                last: i == 1023,
            },
            None,
            &mut rng,
        )
        .await?;
    }
    for i in 0..1024u16 {
        transact(
            &clk,
            &p.0,
            &p.1,
            MemTransaction {
                read: true,
                write: 0,
                addr: i,
                data: 0,
                id: (i & 15) as u8,
                last: i == 1023,
            },
            Some((1023 - i as u32, (i & 15) as u8, i == 1023)),
            &mut rng,
        )
        .await?;
    }
    for i in 0..1024u16 {
        transact(
            &clk,
            &p.0,
            &p.1,
            MemTransaction {
                read: true,
                write: 15,
                addr: i,
                data: i as u32,
                id: (i & 15) as u8,
                last: i == 1023,
            },
            Some((1023 - i as u32, (i & 15) as u8, i == 1023)),
            &mut rng,
        )
        .await?;
    }
    for i in 0..1024u16 {
        transact(
            &clk,
            &p.0,
            &p.1,
            MemTransaction {
                read: true,
                write: 0,
                addr: i,
                data: 0,
                id: (i & 15) as u8,
                last: i == 1023,
            },
            Some((i as u32, (i & 15) as u8, i == 1023)),
            &mut rng,
        )
        .await?;
    }
    Ok(())
}
