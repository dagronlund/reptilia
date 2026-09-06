use std::collections::VecDeque;

use crate::{
    generation::operation,
    transactions::{
        Branch, Cycle, DATA_END, DATA_START, Decode, EBREAK, Expected, MemoryEffect, MemoryRequest,
        Writeback,
    },
};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CheckedInstruction {
    pub expected: Expected,
    pub tag: u8,
}

#[derive(Clone, Debug)]
struct PendingWrite {
    pc: u32,
    generation: u64,
    value: u32,
}

#[derive(Default)]
pub struct Checker {
    writes: [VecDeque<PendingWrite>; 32],
    generations: [u64; 32],
    memory: VecDeque<(u32, MemoryEffect)>,
    branches: VecDeque<(u32, u32, bool, bool, bool)>,
    execution: VecDeque<(u32, bool)>,
    pub architectural: [u32; 32],
    pub compared: usize,
    pub writebacks: usize,
    pub accesses: usize,
    pub resolved: usize,
    pub executed: usize,
    pub flushed: usize,
    pub terminal: bool,
    pub halted: bool,
    pub exit: bool,
    pub last_cycle: u64,
}

impl Checker {
    pub fn accept(
        &mut self,
        decode: Decode,
        expected: Option<&Expected>,
        terminal_pc: u32,
    ) -> Result<(), String> {
        if decode.flushed {
            self.flushed += 1;
            if decode.execute {
                return Err("flushed instruction was dispatched".into());
            }
            return Ok(());
        }
        if self.terminal {
            return Err("architectural instruction accepted after terminal EBREAK".into());
        }
        if decode.instruction == EBREAK {
            if decode.pc != terminal_pc || !decode.execute {
                return Err("unexpected EBREAK/stop dispatch".into());
            }
            self.terminal = true;
            self.execution.push_back((decode.pc, true));
            self.branches.push_back((decode.pc, 0, false, true, true));
            return Ok(());
        }
        let expected = expected.ok_or("missing reference prediction")?;
        if (decode.pc, decode.instruction) != (expected.pc, expected.instruction) {
            return Err(format!(
                "PC/instruction mismatch: DUT {:#010x}:{:#010x}, ISS {:#010x}:{:#010x}",
                decode.pc, decode.instruction, expected.pc, expected.instruction
            ));
        }
        // rd=x0 arithmetic is allowed to disappear in decode; a load still
        // owes its architectural memory access even when its value is unused.
        let opcode = expected.instruction & 127;
        let requires_execute = expected.write.is_some()
            || expected.memory.is_some()
            || opcode == 0x63
            || opcode == 0x6f
            || opcode == 0x67;
        if requires_execute && !decode.execute {
            return Err(format!(
                "{:#010x}: {} was accepted but not dispatched",
                expected.pc,
                operation(expected.instruction)
            ));
        }
        if decode.execute {
            self.execution.push_back((decode.pc, false));
        }
        if let Some((rd, value)) = expected.write {
            let index = rd as usize;
            let generation = self.generations[index];
            if decode.tag != (generation & 7) as u8 {
                return Err(format!(
                    "{:#010x}: x{rd} allocation tag {} expected {} (generation {generation})",
                    decode.pc,
                    decode.tag,
                    generation & 7
                ));
            }
            if self.writes[index].len() >= 7 {
                return Err(format!("x{rd} exhausted live status tags"));
            }
            self.writes[index].push_back(PendingWrite {
                pc: decode.pc,
                generation,
                value,
            });
            self.generations[index] += 1;
        }
        if let Some(effect) = &expected.memory {
            self.memory.push_back((decode.pc, effect.clone()));
        }
        if opcode == 0x63 || opcode == 0x6f || opcode == 0x67 {
            self.branches.push_back((
                decode.pc,
                expected.next_pc,
                opcode == 0x63 && expected.next_pc != decode.pc.wrapping_add(4),
                opcode != 0x63,
                false,
            ));
        }
        self.compared += 1;
        Ok(())
    }

    pub fn writeback(&mut self, write: Writeback) -> Result<(), String> {
        if write.killed {
            // This configuration stalls speculative dispatch. A killed result
            // with no issued architectural instruction is not silently ignored.
            return Err(format!("unexpected killed writeback {write:?}"));
        }
        if write.rd == 0 || !write.writes {
            return Err(format!("unexpected nonarchitectural writeback {write:?}"));
        }
        let queue = &mut self.writes[write.rd as usize];
        let expected = queue
            .front()
            .ok_or_else(|| format!("unexpected/duplicate write to x{}", write.rd))?;
        if write.tag != (expected.generation & 7) as u8 || write.value != expected.value {
            return Err(format!(
                "{:#010x}: x{} generation {} expected tag {} value {:#010x}, got tag {} value {:#010x}",
                expected.pc,
                write.rd,
                expected.generation,
                expected.generation & 7,
                expected.value,
                write.tag,
                write.value
            ));
        }
        queue.pop_front();
        self.architectural[write.rd as usize] = write.value;
        self.writebacks += 1;
        Ok(())
    }

    pub fn memory(&mut self, actual: MemoryRequest) -> Result<(), String> {
        let (pc, expected) = self
            .memory
            .front()
            .ok_or_else(|| format!("unexpected memory request {actual}"))?;
        compare_memory(expected, actual).map_err(|e| format!("{pc:#010x}: {e}"))?;
        self.memory.pop_front();
        self.accesses += 1;
        Ok(())
    }

    pub fn branch(&mut self, actual: Branch) -> Result<(), String> {
        let (pc, target, taken, jumped, halt) = self
            .branches
            .front()
            .ok_or_else(|| format!("unexpected branch {actual:?}"))?;
        if actual.killed || actual.pc != *pc || actual.halt != *halt {
            return Err(format!(
                "branch identity mismatch expected PC {pc:#x}, got {actual:?}"
            ));
        }
        if *halt {
            self.halted = true;
        } else if actual.next_pc != *target || actual.taken != *taken || actual.jumped != *jumped {
            return Err(format!(
                "{pc:#010x}: branch expected next PC {target:#010x}, taken={taken}, jumped={jumped}, got {actual:?}"
            ));
        }
        self.branches.pop_front();
        self.resolved += 1;
        Ok(())
    }

    pub fn observe(
        &mut self,
        cycle: &Cycle,
        expected: Option<&Expected>,
        terminal_pc: u32,
    ) -> Result<(), String> {
        if cycle.number <= self.last_cycle {
            return Err("duplicate/out-of-order cycle sample".into());
        }
        self.last_cycle = cycle.number;
        if cycle.error {
            return Err(format!("DUT error flag at cycle {}", cycle.number));
        }
        // Retire older work first, then allocate new tags. All observation
        // points are separated by registered stages in this wrapper.
        if let Some(write) = cycle.writeback {
            self.writeback(write)?;
        }
        if let Some(memory) = cycle.data {
            self.memory(memory)?;
        }
        if let Some(branch) = cycle.branch {
            self.branch(branch)?;
        }
        if let Some(execution) = cycle.execution {
            let expected = self
                .execution
                .pop_front()
                .ok_or("unexpected execute completion")?;
            if execution.killed || (execution.pc, execution.halt) != expected {
                return Err(format!(
                    "execute completion mismatch: expected {expected:?}, got {execution:?}"
                ));
            }
            self.executed += 1;
        }
        if let Some(decode) = cycle.decode {
            self.accept(decode, expected, terminal_pc)?;
        }
        self.exit |= cycle.exit;
        Ok(())
    }

    pub fn drained(&self) -> bool {
        (&self.writes).into_iter().all(VecDeque::is_empty)
            && self.memory.is_empty()
            && self.branches.is_empty()
            && self.execution.is_empty()
    }

    pub fn finish(
        &self,
        registers: &[u32; 32],
        dut_memory: &[u8],
        reference_memory: &[u8],
    ) -> Result<(), String> {
        if self.compared == 0 {
            return Err("nothing was compared".into());
        }
        if !self.terminal || !self.halted || !self.exit || !self.drained() {
            return Err(format!(
                "incomplete execution: terminal={} halt={} exit={} pending: {}",
                self.terminal,
                self.halted,
                self.exit,
                self.pending()
            ));
        }
        if &self.architectural != registers {
            return Err(format!(
                "final architectural register mismatch: observed={:?}, expected={registers:?}",
                self.architectural
            ));
        }
        if dut_memory != reference_memory {
            let offset = dut_memory
                .into_iter()
                .zip(reference_memory)
                .position(|(a, b)| a != b)
                .unwrap_or(0);
            return Err(format!("final memory differs at {offset:#010x}"));
        }
        Ok(())
    }

    pub fn pending(&self) -> String {
        format!(
            "register writes={}, memory={}, branches={}, execution={}",
            (&self.writes).into_iter().map(VecDeque::len).sum::<usize>(),
            self.memory.len(),
            self.branches.len(),
            self.execution.len()
        )
    }
}

pub fn compare_memory(expected: &MemoryEffect, actual: MemoryRequest) -> Result<(), String> {
    if actual.address < DATA_START || actual.address >= DATA_END {
        return Err(format!("data request outside data region: {actual}"));
    }
    if actual.address != expected.address || actual.read != expected.read {
        return Err(format!("memory expected {expected:?}, got {actual}"));
    }
    let lane = expected.address & 3;
    let mask = if expected.read {
        0
    } else {
        ((1u8 << expected.bytes) - 1) << lane
    };
    if actual.mask != mask {
        return Err(format!(
            "memory byte mask expected {mask:#x}, got {:#x}",
            actual.mask
        ));
    }
    if !expected.read {
        let mut enabled_bits = 0u32;
        for index in 0..4 {
            if mask & (1 << index) != 0 {
                enabled_bits |= 255 << (8 * index);
            }
        }
        if actual.data & enabled_bits != (expected.value << (8 * lane)) & enabled_bits {
            return Err(format!(
                "store value mismatch expected {expected:?}, got {actual}"
            ));
        }
    }
    Ok(())
}
