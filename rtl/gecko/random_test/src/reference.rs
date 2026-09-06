use rrs_lib::{
    HartState, MemAccessSize, Memory, instruction_executor::InstructionExecutor,
    instruction_string_outputter::InstructionStringOutputter, process_instruction,
};

use crate::transactions::{EBREAK, Expected, MemoryEffect, Program};

pub fn disassemble(pc: u32, instruction: u32) -> String {
    if instruction == EBREAK {
        return "ebreak (harness stop)".to_string();
    }
    process_instruction(&mut InstructionStringOutputter { insn_pc: pc }, instruction)
        .unwrap_or_else(|| format!(".word {instruction:#010x}"))
}

pub struct ReferenceMemory {
    pub bytes: Vec<u8>,
    accesses: Vec<MemoryEffect>,
}

fn width(size: MemAccessSize) -> usize {
    match size {
        MemAccessSize::Byte => 1,
        MemAccessSize::HalfWord => 2,
        MemAccessSize::Word => 4,
    }
}

impl Memory for ReferenceMemory {
    fn read_mem(&mut self, address: u32, size: MemAccessSize) -> Option<u32> {
        let bytes = width(size);
        let slice = self.bytes.get(address as usize..address as usize + bytes)?;
        let mut raw = [0; 4];
        raw[..bytes].copy_from_slice(slice);
        let value = u32::from_le_bytes(raw);
        self.accesses.push(MemoryEffect {
            read: true,
            address,
            bytes,
            value,
        });
        Some(value)
    }

    fn write_mem(&mut self, address: u32, size: MemAccessSize, value: u32) -> bool {
        let bytes = width(size);
        let Some(slice) = self
            .bytes
            .get_mut(address as usize..address as usize + bytes)
        else {
            return false;
        };
        slice.copy_from_slice(&value.to_le_bytes()[..bytes]);
        self.accesses.push(MemoryEffect {
            read: false,
            address,
            bytes,
            value,
        });
        true
    }
}

pub struct ReferenceModel {
    pub hart: HartState,
    pub memory: ReferenceMemory,
}

impl ReferenceModel {
    pub fn new(program: &Program) -> Self {
        Self {
            hart: HartState::new(),
            memory: ReferenceMemory {
                bytes: program.memory.clone(),
                accesses: Vec::new(),
            },
        }
    }

    pub fn step(&mut self) -> Result<Expected, String> {
        let pc = self.hart.pc;
        let raw = self
            .memory
            .bytes
            .get(pc as usize..pc as usize + 4)
            .ok_or_else(|| format!("ISS PC outside memory: {pc:#x}"))?;
        let instruction = u32::from_le_bytes(raw.try_into().unwrap());
        if instruction == EBREAK {
            return Err("stop instruction must be handled by the harness".into());
        }
        let operands = [
            self.hart.registers[((instruction >> 15) & 31) as usize],
            self.hart.registers[((instruction >> 20) & 31) as usize],
        ];
        self.memory.accesses.clear();
        InstructionExecutor {
            hart_state: &mut self.hart,
            mem: &mut self.memory,
        }
        .step()
        .map_err(|e| format!("ISS at {pc:#010x} ({instruction:#010x}): {e:?}"))?;
        // The first read belongs to InstructionExecutor's own fetch, not the
        // data interface. Anything after it is the instruction's memory effect.
        if self.memory.accesses.len() > 2 {
            return Err("ISS produced multiple data accesses".into());
        }
        let memory = self.memory.accesses.get(1).cloned();
        let write = self
            .hart
            .last_register_write
            .map(|rd| (rd as u8, self.hart.registers[rd]));
        Ok(Expected {
            pc,
            instruction,
            next_pc: self.hart.pc,
            write,
            memory,
            operands,
        })
    }
}
