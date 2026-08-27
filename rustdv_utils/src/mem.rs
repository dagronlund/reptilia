use rustdv::prelude::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MemTransaction {
    pub read: bool,
    pub write: u8,
    pub addr: u16,
    pub data: u32,
    pub id: u8,
    pub last: bool,
}

#[derive(Clone, Copy)]
pub struct MemPort {
    pub valid: LogicHandle,
    pub ready: LogicHandle,
    pub read_enable: LogicHandle,
    pub write_enable: LogicHandle,
    pub addr: LogicHandle,
    pub data: LogicHandle,
    pub id: LogicHandle,
    pub last: LogicHandle,
}

impl MemPort {
    pub fn new(dut: &HierarchyHandle, name: &str) -> Result<Self, HandleError> {
        Ok(Self {
            valid: dut.signal(&format!("{name}.valid"))?,
            ready: dut.signal(&format!("{name}.ready"))?,
            read_enable: dut.signal(&format!("{name}.read_enable"))?,
            write_enable: dut.signal(&format!("{name}.write_enable"))?,
            addr: dut.signal(&format!("{name}.addr"))?,
            data: dut.signal(&format!("{name}.data"))?,
            id: dut.signal(&format!("{name}.id"))?,
            last: dut.signal(&format!("{name}.last"))?,
        })
    }

    pub fn idle_input(&self) {
        self.valid.set_u64(0);
    }

    pub fn drive(&self, transaction: MemTransaction) {
        self.read_enable.set_u64(transaction.read as u64);
        self.write_enable.set_u64(transaction.write as u64);
        self.addr.set_u64(transaction.addr as u64);
        self.data.set_u64(transaction.data as u64);
        self.id.set_u64(transaction.id as u64);
        self.last.set_u64(transaction.last as u64);
    }

    pub fn idle_output(&self) {
        self.ready.set_u64(0);
    }
}
