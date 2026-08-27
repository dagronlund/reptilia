use rustdv::prelude::*;

#[derive(Clone, Copy)]
pub struct StreamPort {
    pub valid: LogicHandle,
    pub ready: LogicHandle,
    pub payload: LogicHandle,
}

impl StreamPort {
    pub fn new(dut: &HierarchyHandle, name: &str) -> Result<Self, HandleError> {
        Ok(Self {
            valid: dut.signal(&format!("{name}.valid"))?,
            ready: dut.signal(&format!("{name}.ready"))?,
            payload: dut.signal(&format!("{name}.payload"))?,
        })
    }

    pub fn idle_input(&self) {
        self.valid.set_u64(0);
        self.payload.set_u64(0);
    }

    pub fn idle_output(&self) {
        self.ready.set_u64(0);
    }
}
