use std::ops::Range;

use rustdv::prelude::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MemTransaction {
    pub read: bool,
    pub write: u8,
    pub addr: u32,
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

pub struct MemoryPortDual {
    request: MemPort,
    result: MemPort,
    next_request: Option<MemTransaction>,
    result_valid: bool,
    result_accepted: bool,
}

impl MemoryPortDual {
    pub fn new(dut: &HierarchyHandle, request: &str, result: &str) -> Result<Self, TestError> {
        let request =
            MemPort::new(dut, request).map_err(|error| TestError::new(error.to_string()))?;
        let result =
            MemPort::new(dut, result).map_err(|error| TestError::new(error.to_string()))?;
        request.ready.set_u64(0);
        result.valid.set_u64(0);
        result.read_enable.set_u64(0);
        result.write_enable.set_u64(0);
        result.addr.set_u64(0);
        result.data.set_u64(0);
        result.id.set_u64(0);
        result.last.set_u64(0);
        Ok(Self {
            request,
            result,
            next_request: None,
            result_valid: false,
            result_accepted: false,
        })
    }

    pub fn start_cycle(&mut self, memory: &mut [u8]) -> Result<(), TestError> {
        if self.result_accepted {
            self.result_valid = false;
            self.result.valid.set_u64(0);
        }
        if let Some(request) = self.next_request.take() {
            write_memory(memory, request)?;
            if request.read {
                let data = read_memory(memory, request.addr)?;
                self.result.read_enable.set_u64(1);
                self.result.write_enable.set_u64(0);
                self.result.addr.set_u64(u64::from(request.addr));
                self.result.data.set_u64(u64::from(data));
                self.result.id.set_u64(u64::from(request.id));
                self.result.last.set_u64(request.last as u64);
                self.result.valid.set_u64(1);
                self.result_valid = true;
            }
        }
        let result_will_advance = self.result_valid && self.result.ready.is_high();
        self.request
            .ready
            .set_u64((!self.result_valid || result_will_advance) as u64);
        Ok(())
    }

    pub fn end_cycle(&mut self) -> Result<(), TestError> {
        self.next_request = if self.request.valid.is_high() && self.request.ready.is_high() {
            Some(MemTransaction {
                read: self.request.read_enable.is_high(),
                write: self
                    .request
                    .write_enable
                    .get_u64()
                    .map_err(|error| TestError::new(error.to_string()))?
                    as u8,
                addr: self
                    .request
                    .addr
                    .get_u64()
                    .map_err(|error| TestError::new(error.to_string()))?
                    as u32,
                data: self
                    .request
                    .data
                    .get_u64()
                    .map_err(|error| TestError::new(error.to_string()))?
                    as u32,
                id: self
                    .request
                    .id
                    .get_u64()
                    .map_err(|error| TestError::new(error.to_string()))? as u8,
                last: self.request.last.is_high(),
            })
        } else {
            None
        };
        self.result_accepted = self.result_valid && self.result.ready.is_high();
        Ok(())
    }
}

fn word_range(memory: &[u8], addr: u32) -> Result<Range<usize>, TestError> {
    let start = (addr as usize) & !3;
    let end = start
        .checked_add(4)
        .ok_or_else(|| TestError::new(format!("memory address overflow at {addr:#010x}")))?;
    if end > memory.len() {
        return Err(TestError::new(format!(
            "memory access outside shared memory at {addr:#010x}",
        )));
    }
    Ok(start..end)
}

fn read_memory(memory: &[u8], addr: u32) -> Result<u32, TestError> {
    let range = word_range(memory, addr)?;
    let bytes: [u8; 4] = memory[range]
        .try_into()
        .map_err(|_| TestError::new("memory word did not contain four bytes"))?;
    Ok(u32::from_le_bytes(bytes))
}

fn write_memory(memory: &mut [u8], request: MemTransaction) -> Result<(), TestError> {
    if request.write == 0 {
        return Ok(());
    }
    let range = word_range(memory, request.addr)?;
    let start = range.start;
    let bytes = request.data.to_le_bytes();
    for lane in 0..4 {
        if request.write & (1 << lane) != 0 {
            memory[start + lane] = bytes[lane];
        }
    }
    Ok(())
}
