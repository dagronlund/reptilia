use std::{env, fmt, path::PathBuf};

use rustdv::prelude::*;

pub const MEMORY_BYTES: usize = 65536;
pub const DATA_START: u32 = 0x8000;
pub const DATA_END: u32 = 0xf000;
pub const EBREAK: u32 = 0x0010_0073;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Config {
    pub seed: u64,
    pub instructions: usize,
    pub max_cycles: u64,
    pub artifacts: PathBuf,
    pub trace_config: bool,
    pub replay: Option<PathBuf>,
}

impl Config {
    pub fn from_context(ctx: &RustdvCtx) -> Result<Self, TestError> {
        let instructions = match env::var("GECKO_RANDOM_INSTRUCTIONS") {
            Ok(value) => value
                .parse::<usize>()
                .map_err(|e| TestError::new(e.to_string()))?,
            Err(env::VarError::NotPresent) => 1000,
            Err(e) => return Err(TestError::new(e.to_string())),
        };
        if instructions > 4000 {
            return Err(TestError::new("GECKO_RANDOM_INSTRUCTIONS must be <= 4000"));
        }
        let root = env::var_os("GECKO_RANDOM_ARTIFACTS")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("build/rustdv/gecko-random"));
        Ok(Self {
            seed: ctx.seed(),
            instructions,
            max_cycles: 200_000,
            artifacts: root.join(format!("{}-seed-{}", ctx.path(), ctx.seed())),
            trace_config: env::var_os("GECKO_RANDOM_CONFIG_TRACE").is_some(),
            replay: env::var_os("GECKO_RANDOM_REPLAY").map(PathBuf::from),
        })
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Program {
    pub words: Vec<u32>,
    pub memory: Vec<u8>,
    pub terminal_pc: u32,
}

impl fmt::Display for Program {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{} instructions, terminal PC={:#010x}",
            self.words.len(),
            self.terminal_pc
        )
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct MemoryRequest {
    pub read: bool,
    pub mask: u8,
    pub address: u32,
    pub data: u32,
    pub id: u8,
    pub last: bool,
}

impl fmt::Display for MemoryRequest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "{} @{:#010x} data={:#010x} mask={:#x}",
            if self.read { "read" } else { "write" },
            self.address,
            self.data,
            self.mask
        )
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MemoryPlan {
    pub request: MemoryRequest,
    pub delay: u64,
    pub stall: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Completion {
    pub cycles: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Decode {
    pub pc: u32,
    pub instruction: u32,
    pub tag: u8,
    pub execute: bool,
    pub flushed: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Execution {
    pub pc: u32,
    pub killed: bool,
    pub halt: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Writeback {
    pub rd: u8,
    pub tag: u8,
    pub value: u32,
    pub killed: bool,
    pub writes: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Branch {
    pub pc: u32,
    pub next_pc: u32,
    pub taken: bool,
    pub jumped: bool,
    pub killed: bool,
    pub halt: bool,
}

/// A single monitor publishes one atomic pre-edge sample. Subscribers never
/// infer a cross-stream ordering from the executor's task scheduling order.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Cycle {
    pub number: u64,
    pub injected_writeback: bool,
    pub decode: Option<Decode>,
    pub execution: Option<Execution>,
    pub writeback: Option<Writeback>,
    pub branch: Option<Branch>,
    pub data: Option<MemoryRequest>,
    pub exit: bool,
    pub error: bool,
}

impl fmt::Display for Cycle {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "cycle {} decode={:?} execute={:?} wb={:?} branch={:?} memory={:?} exit={} error={}",
            self.number,
            self.decode,
            self.execution,
            self.writeback,
            self.branch,
            self.data,
            self.exit,
            self.error
        )
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MemoryEffect {
    pub read: bool,
    pub address: u32,
    pub bytes: usize,
    pub value: u32,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Expected {
    pub pc: u32,
    pub instruction: u32,
    pub next_pc: u32,
    pub write: Option<(u8, u32)>,
    pub memory: Option<MemoryEffect>,
    pub operands: [u32; 2],
}
