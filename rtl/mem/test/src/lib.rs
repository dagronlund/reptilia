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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct MemTransaction {
    read: bool,
    write: u8,
    addr: u16,
    data: u32,
    id: u8,
    last: bool,
}

#[derive(Clone, Copy)]
struct MemInputPort {
    valid: LogicHandle,
    ready: LogicHandle,
    read: LogicHandle,
    write: LogicHandle,
    addr: LogicHandle,
    data: LogicHandle,
    id: LogicHandle,
    last: LogicHandle,
}

impl MemInputPort {
    fn new(dut: &HierarchyHandle, name: &str) -> Result<Self, HandleError> {
        Ok(Self {
            valid: dut.signal(&format!("{name}.valid"))?,
            ready: dut.signal(&format!("{name}.ready"))?,
            read: dut.signal(&format!("{name}.read_enable"))?,
            write: dut.signal(&format!("{name}.write_enable"))?,
            addr: dut.signal(&format!("{name}.addr"))?,
            data: dut.signal(&format!("{name}.data"))?,
            id: dut.signal(&format!("{name}.id"))?,
            last: dut.signal(&format!("{name}.last"))?,
        })
    }

    fn idle(&self) {
        self.valid.set_u64(0);
    }

    fn drive(&self, t: MemTransaction) {
        self.read.set_u64(t.read as u64);
        self.write.set_u64(t.write as u64);
        self.addr.set_u64(t.addr as u64);
        self.data.set_u64(t.data as u64);
        self.id.set_u64(t.id as u64);
        self.last.set_u64(t.last as u64);
    }
}

#[derive(Clone, Copy)]
struct MemOutputPort {
    valid: LogicHandle,
    ready: LogicHandle,
    data: LogicHandle,
    id: LogicHandle,
    last: LogicHandle,
}

impl MemOutputPort {
    fn new(dut: &HierarchyHandle, name: &str) -> Result<Self, HandleError> {
        Ok(Self {
            valid: dut.signal(&format!("{name}.valid"))?,
            ready: dut.signal(&format!("{name}.ready"))?,
            data: dut.signal(&format!("{name}.data"))?,
            id: dut.signal(&format!("{name}.id"))?,
            last: dut.signal(&format!("{name}.last"))?,
        })
    }

    fn idle(&self) {
        self.ready.set_u64(0);
    }
}

async fn start(
    dut: &HierarchyHandle,
    ports: &[(MemInputPort, MemOutputPort)],
) -> Result<LogicHandle, TestError> {
    let clk = dut
        .signal("clk")
        .map_err(|e| TestError::new(e.to_string()))?;
    let rst = dut
        .signal("rst")
        .map_err(|e| TestError::new(e.to_string()))?;
    for (input, output) in ports {
        input.idle();
        output.idle();
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
    input: &MemInputPort,
    output: &MemOutputPort,
    t: MemTransaction,
    expected: Option<(u32, u8, bool)>,
    rng: &mut Rng,
) -> Result<(), TestError> {
    let mut accepted = false;
    for _ in 0..1000 {
        clk.falling_edge().await;
        input.drive(t);
        input.valid.set_u64((!accepted) as u64);
        output.ready.set_u64(rng.bool() as u64);
        Timer::ns(4).await;
        if !accepted && input.ready.is_high() {
            accepted = true;
        }
        if output.valid.is_high() && output.ready.is_high() {
            let Some((data, id, last)) = expected else {
                return Err(TestError::new("unexpected memory response"));
            };
            if output.data.get_u64() != Ok(data as u64)
                || output.id.get_u64() != Ok(id as u64)
                || output.last.is_high() != last
            {
                return Err(TestError::new(format!(
                    "memory response mismatch at {}",
                    t.addr
                )));
            }
            clk.rising_edge().await;
            return Ok(());
        }
        if accepted && expected.is_none() {
            clk.rising_edge().await;
            return Ok(());
        }
    }
    Err(TestError::new(format!(
        "memory transaction timed out at {}",
        t.addr
    )))
}
