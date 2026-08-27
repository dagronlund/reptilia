mod double;
mod read_write;
mod single;
mod split_merge;

#[cfg(test)]
mod tests;

use rustdv::prelude::*;

#[cfg(test)]
use rustdv_vpi_stubs as _;

rustdv::vpi_bootstrap!();

fn fail(message: impl Into<String>) -> TestError {
    TestError::new(message.into())
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct MemTxn {
    read: bool,
    write: u8,
    addr: u16,
    data: u32,
    id: u8,
    last: bool,
}

#[derive(Clone, Copy)]
struct MemPort {
    valid: LogicHandle,
    ready: LogicHandle,
    read: LogicHandle,
    write: LogicHandle,
    addr: LogicHandle,
    data: LogicHandle,
    id: LogicHandle,
    last: LogicHandle,
    out_valid: LogicHandle,
    out_ready: LogicHandle,
    out_data: LogicHandle,
    out_id: LogicHandle,
    out_last: LogicHandle,
}

impl MemPort {
    fn new(dut: &HierarchyHandle, input: &str, output: &str) -> Result<Self, HandleError> {
        Ok(Self {
            valid: dut.signal(&format!("{input}_valid"))?,
            ready: dut.signal(&format!("{input}_ready"))?,
            read: dut.signal(&format!("{input}_read"))?,
            write: dut.signal(&format!("{input}_write"))?,
            addr: dut.signal(&format!("{input}_addr"))?,
            data: dut.signal(&format!("{input}_data"))?,
            id: dut.signal(&format!("{input}_id"))?,
            last: dut.signal(&format!("{input}_last"))?,
            out_valid: dut.signal(&format!("{output}_valid"))?,
            out_ready: dut.signal(&format!("{output}_ready"))?,
            out_data: dut.signal(&format!("{output}_data"))?,
            out_id: dut.signal(&format!("{output}_id"))?,
            out_last: dut.signal(&format!("{output}_last"))?,
        })
    }
    fn idle(&self) {
        self.valid.set_u64(0);
        self.out_ready.set_u64(0);
    }
    fn drive(&self, t: MemTxn) {
        self.read.set_u64(t.read as u64);
        self.write.set_u64(t.write as u64);
        self.addr.set_u64(t.addr as u64);
        self.data.set_u64(t.data as u64);
        self.id.set_u64(t.id as u64);
        self.last.set_u64(t.last as u64);
    }
}

async fn start(dut: &HierarchyHandle, ports: &[MemPort]) -> Result<LogicHandle, TestError> {
    let clk = dut.signal("clk").map_err(|e| fail(e.to_string()))?;
    let rst = dut.signal("rst").map_err(|e| fail(e.to_string()))?;
    for p in ports {
        p.idle();
    }
    rst.set_u64(1);
    let _clock = Clock::new(&clk, SimDuration::ns(10)).start();
    for _ in 0..5 {
        clk.falling_edge().await;
    }
    rst.set_u64(0);
    clk.falling_edge().await;
    Ok(clk)
}

async fn transact(
    clk: &LogicHandle,
    p: &MemPort,
    t: MemTxn,
    expected: Option<(u32, u8, bool)>,
    rng: &mut Rng,
) -> Result<(), TestError> {
    let mut accepted = false;
    for _ in 0..1000 {
        clk.falling_edge().await;
        p.drive(t);
        p.valid.set_u64((!accepted) as u64);
        p.out_ready.set_u64(rng.bool() as u64);
        Timer::ns(4).await;
        if !accepted && p.ready.is_high() {
            accepted = true;
        }
        if p.out_valid.is_high() && p.out_ready.is_high() {
            let Some((data, id, last)) = expected else {
                return Err(fail("unexpected memory response"));
            };
            if p.out_data.get_u64() != Ok(data as u64)
                || p.out_id.get_u64() != Ok(id as u64)
                || p.out_last.is_high() != last
            {
                return Err(fail(format!("memory response mismatch at {}", t.addr)));
            }
            clk.rising_edge().await;
            return Ok(());
        }
        if accepted && expected.is_none() {
            clk.rising_edge().await;
            return Ok(());
        }
    }
    Err(fail(format!("memory transaction timed out at {}", t.addr)))
}
