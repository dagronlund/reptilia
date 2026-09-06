use std::{
    cell::{Cell, RefCell},
    collections::BTreeMap,
    fmt, fs,
    rc::Rc,
};

use rustdv::prelude::*;
use rustdv_utils::{mem::MemPort, stream::StreamPort};

use crate::{
    reference::ReferenceModel,
    transactions::{
        Branch, Config, Cycle, DATA_END, DATA_START, Decode, Execution, MEMORY_BYTES,
        MemoryRequest, Program, Writeback,
    },
};

pub struct Session {
    pub config: Config,
    pub memory: RefCell<Vec<u8>>,
    pub reference: RefCell<Option<ReferenceModel>>,
    pub program: RefCell<Option<Program>>,
    pub started: Event,
    pub done: Event,
    pub failed: Event,
    pub error: RefCell<Option<TestError>>,
    pub cycles: Cell<u64>,
    pub accepted: [Cell<u64>; 2],
    pub serviced: [Cell<u64>; 2],
    pub busy: [Cell<bool>; 2],
    pub passive_seen: Cell<u64>,
    pub passive_expected: Cell<bool>,
}

impl fmt::Debug for Session {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Session")
            .field("config", &self.config)
            .finish_non_exhaustive()
    }
}

impl Session {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            memory: RefCell::new(vec![0; MEMORY_BYTES]),
            reference: RefCell::new(None),
            program: RefCell::new(None),
            started: Event::new(),
            done: Event::new(),
            failed: Event::new(),
            error: RefCell::new(None),
            cycles: Cell::new(0),
            accepted: [Cell::new(0), Cell::new(0)],
            serviced: [Cell::new(0), Cell::new(0)],
            busy: [Cell::new(false), Cell::new(false)],
            passive_seen: Cell::new(0),
            passive_expected: Cell::new(false),
        }
    }

    pub fn install(&self, program: Program) {
        *self.memory.borrow_mut() = program.memory.clone();
        *self.reference.borrow_mut() = Some(ReferenceModel::new(&program));
        *self.program.borrow_mut() = Some(program);
    }

    pub fn idle(&self) -> bool {
        (0..2).all(|n| !self.busy[n].get() && self.accepted[n].get() == self.serviced[n].get())
    }

    pub fn fail(&self, error: TestError) -> TestError {
        if self.error.borrow().is_none() {
            *self.error.borrow_mut() = Some(error.clone());
            let _ = fs::write(
                self.config.artifacts.join("failure.txt"),
                format!("{error}\n"),
            );
        }
        self.failed.set();
        error
    }
}

pub struct CoreBfm {
    pub clk: LogicHandle,
    rst: LogicHandle,
    handles: BTreeMap<String, LogicHandle>,
    data: MemPort,
}

impl fmt::Debug for CoreBfm {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("CoreBfm(read-only architectural observations, reset)")
    }
}

impl CoreBfm {
    pub fn new(dut: &HierarchyHandle) -> Result<Self, TestError> {
        let mut handles = BTreeMap::new();
        for name in [
            "reset_done",
            "decode_valid",
            "decode_flush",
            "decode_pc",
            "decode_instruction",
            "decode_tag",
            "decode_execute",
            "execute_valid",
            "execute_pc",
            "execute_killed",
            "execute_halt",
            "wb_valid",
            "wb_rd",
            "wb_tag",
            "wb_value",
            "wb_killed",
            "wb_writes",
            "branch_valid",
            "branch_pc",
            "branch_next_pc",
            "branch_taken",
            "branch_jumped",
            "branch_killed",
            "branch_halt",
        ] {
            handles.insert(name.to_string(), dut.signal(&format!("trace_{name}"))?);
        }
        for reg in 0..32 {
            handles.insert(
                format!("reg_{reg}"),
                dut.signal(&format!("trace_reg[{reg}]"))?,
            );
        }
        for name in ["exit_flag", "error_flag"] {
            handles.insert(name.to_string(), dut.signal(name)?);
        }
        MemPort::new(dut, "float_mem_request")?.ready.set_u64(0);
        MemPort::new(dut, "float_mem_result")?.valid.set_u64(0);
        StreamPort::new(dut, "tty_in")?.idle_input();
        StreamPort::new(dut, "tty_out")?.ready.set_u64(1);
        Ok(Self {
            clk: dut.signal("clk")?,
            rst: dut.signal("rst")?,
            handles,
            data: MemPort::new(dut, "data_request")?,
        })
    }

    fn value(&self, name: &str) -> Result<u32, TestError> {
        Ok(self.handles[name].get_u64()? as u32)
    }
    fn high(&self, name: &str) -> bool {
        self.handles[name].is_high()
    }

    pub async fn reset(&self) -> Result<(), TestError> {
        self.rst.set_u64(1);
        for _ in 0..5 {
            self.clk.falling_edge().await;
        }
        self.rst.set_u64(0);
        for _ in 0..64 {
            self.clk.falling_edge().await;
            if self.high("reset_done") {
                return Ok(());
            }
        }
        Err(TestError::new("register-file reset did not complete"))
    }

    pub fn registers(&self) -> Result<[u32; 32], TestError> {
        let mut registers = [0; 32];
        for (reg, value) in (&mut registers).into_iter().enumerate() {
            *value = self.value(&format!("reg_{reg}"))?;
        }
        Ok(registers)
    }

    pub fn sample(&self, number: u64) -> Result<Cycle, TestError> {
        Ok(Cycle {
            number,
            injected_writeback: false,
            decode: if self.high("decode_valid") {
                Some(Decode {
                    pc: self.value("decode_pc")?,
                    instruction: self.value("decode_instruction")?,
                    tag: self.value("decode_tag")? as u8,
                    execute: self.high("decode_execute"),
                    flushed: self.high("decode_flush"),
                })
            } else {
                None
            },
            execution: if self.high("execute_valid") {
                Some(Execution {
                    pc: self.value("execute_pc")?,
                    killed: self.high("execute_killed"),
                    halt: self.high("execute_halt"),
                })
            } else {
                None
            },
            writeback: if self.high("wb_valid") {
                Some(Writeback {
                    rd: self.value("wb_rd")? as u8,
                    tag: self.value("wb_tag")? as u8,
                    value: self.value("wb_value")?,
                    killed: self.high("wb_killed"),
                    writes: self.high("wb_writes"),
                })
            } else {
                None
            },
            branch: if self.high("branch_valid") {
                Some(Branch {
                    pc: self.value("branch_pc")?,
                    next_pc: self.value("branch_next_pc")?,
                    taken: self.high("branch_taken"),
                    jumped: self.high("branch_jumped"),
                    killed: self.high("branch_killed"),
                    halt: self.high("branch_halt"),
                })
            } else {
                None
            },
            data: accepted(&self.data)?,
            exit: self.high("exit_flag"),
            error: self.high("error_flag"),
        })
    }
}

pub fn accepted(port: &MemPort) -> Result<Option<MemoryRequest>, TestError> {
    if !port.valid.is_high() || !port.ready.is_high() {
        return Ok(None);
    }
    Ok(Some(payload(port)?))
}

pub fn payload(port: &MemPort) -> Result<MemoryRequest, TestError> {
    Ok(MemoryRequest {
        read: port.read_enable.is_high(),
        mask: port.write_enable.get_u64()? as u8,
        address: port.addr.get_u64()? as u32,
        data: port.data.get_u64()? as u32,
        id: port.id.get_u64()? as u8,
        last: port.last.is_high(),
    })
}

pub struct MemoryBfm {
    pub clk: LogicHandle,
    pub request: MemPort,
    pub result: MemPort,
    pub index: usize,
    pub session: Rc<Session>,
    pub responses: Queue<MemoryRequest>,
}

impl fmt::Debug for MemoryBfm {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "MemoryBfm(port={})", self.index)
    }
}

impl MemoryBfm {
    pub fn new(
        dut: &HierarchyHandle,
        index: usize,
        session: Rc<Session>,
    ) -> Result<Self, TestError> {
        let stem = if index == 0 { "inst" } else { "data" };
        let request = MemPort::new(dut, &format!("{stem}_request"))?;
        let result = MemPort::new(dut, &format!("{stem}_result"))?;
        request.ready.set_u64(0);
        result.valid.set_u64(0);
        result.drive(rustdv_utils::mem::MemTransaction {
            read: false,
            write: 0,
            addr: 0,
            data: 0,
            id: 0,
            last: false,
        });
        Ok(Self {
            clk: dut.signal("clk")?,
            request,
            result,
            index,
            session,
            responses: Queue::unbounded(),
        })
    }

    pub fn access(&self, request: MemoryRequest) -> Result<u32, TestError> {
        access_memory(&mut self.session.memory.borrow_mut(), self.index, request)
            .map_err(TestError::new)
    }
}

/// Independent DUT-side byte-lane implementation; the ISS uses Memory's
/// byte/halfword/word operations instead of sharing this implementation.
pub fn access_memory(
    memory: &mut [u8],
    port: usize,
    request: MemoryRequest,
) -> Result<u32, String> {
    if port == 0 && (!request.read || request.mask != 0 || request.address >= DATA_START) {
        return Err(format!("invalid instruction request {request}"));
    }
    if port == 1
        && (request.address < DATA_START
            || request.address >= DATA_END
            || (request.read && request.mask != 0)
            || (!request.read && request.mask == 0))
    {
        return Err(format!("invalid data request {request}"));
    }
    let start = request.address as usize & !3;
    let word = memory
        .get_mut(start..start + 4)
        .ok_or("memory request outside allocation")?;
    for (lane, byte) in word.into_iter().enumerate() {
        if request.mask & (1 << lane) != 0 {
            *byte = (request.data >> (lane * 8)) as u8;
        }
    }
    Ok(u32::from_le_bytes(
        memory[start..start + 4].try_into().unwrap(),
    ))
}
