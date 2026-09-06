use std::{fs, path::Path};

use rustdv::prelude::Rng;

use crate::transactions::{DATA_END, DATA_START, EBREAK, MEMORY_BYTES, Program};

pub const OPERATIONS: [&str; 39] = [
    "add", "sub", "sll", "slt", "sltu", "xor", "srl", "sra", "or", "and", "addi", "slti", "sltiu",
    "xori", "ori", "andi", "slli", "srli", "srai", "lui", "auipc", "beq", "bne", "blt", "bge",
    "bltu", "bgeu", "jal", "jalr", "lb", "lh", "lw", "lbu", "lhu", "sb", "sh", "sw", "fence",
    "fence.i",
];

pub fn operation(word: u32) -> &'static str {
    let funct = (word >> 12) & 7;
    match word & 127 {
        0x33 => match (funct, word >> 25) {
            (0, 32) => "sub",
            (5, 32) => "sra",
            (0, _) => "add",
            (1, _) => "sll",
            (2, _) => "slt",
            (3, _) => "sltu",
            (4, _) => "xor",
            (5, _) => "srl",
            (6, _) => "or",
            _ => "and",
        },
        0x13 => match funct {
            0 => "addi",
            1 => "slli",
            2 => "slti",
            3 => "sltiu",
            4 => "xori",
            5 if word >> 25 == 32 => "srai",
            5 => "srli",
            6 => "ori",
            _ => "andi",
        },
        0x0f if funct == 0 => "fence",
        0x0f if funct == 1 => "fence.i",
        0x37 => "lui",
        0x17 => "auipc",
        0x6f => "jal",
        0x67 => "jalr",
        0x63 => match funct {
            0 => "beq",
            1 => "bne",
            4 => "blt",
            5 => "bge",
            6 => "bltu",
            _ => "bgeu",
        },
        0x03 => match funct {
            0 => "lb",
            1 => "lh",
            2 => "lw",
            4 => "lbu",
            _ => "lhu",
        },
        0x23 => match funct {
            0 => "sb",
            1 => "sh",
            _ => "sw",
        },
        _ => "stop",
    }
}

pub fn r(funct: u32, alternate: bool, rd: u32, rs1: u32, rs2: u32) -> u32 {
    ((alternate as u32) << 30) | (rs2 << 20) | (rs1 << 15) | (funct << 12) | (rd << 7) | 0x33
}

pub fn i(opcode: u32, funct: u32, rd: u32, rs1: u32, immediate: i32) -> u32 {
    ((immediate as u32 & 0xfff) << 20) | (rs1 << 15) | (funct << 12) | (rd << 7) | opcode
}

pub fn s(funct: u32, rs1: u32, rs2: u32, immediate: i32) -> u32 {
    let imm = immediate as u32 & 0xfff;
    ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct << 12) | ((imm & 31) << 7) | 0x23
}

pub fn b(funct: u32, rs1: u32, rs2: u32, offset: i32) -> u32 {
    let imm = offset as u32;
    ((imm >> 12 & 1) << 31)
        | ((imm >> 5 & 63) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct << 12)
        | ((imm >> 1 & 15) << 8)
        | ((imm >> 11 & 1) << 7)
        | 0x63
}

pub fn j(rd: u32, offset: i32) -> u32 {
    let imm = offset as u32;
    ((imm >> 20 & 1) << 31)
        | ((imm >> 1 & 1023) << 21)
        | ((imm >> 11 & 1) << 20)
        | ((imm >> 12 & 255) << 12)
        | (rd << 7)
        | 0x6f
}

pub fn li(words: &mut Vec<u32>, rd: u32, value: u32) {
    let hi = value.wrapping_add(0x800) & 0xfffff000;
    words.push(hi | (rd << 7) | 0x37);
    words.push(i(0x13, 0, rd, rd, value as i32));
}

fn jumps(words: &mut Vec<u32>, odd_target: bool) {
    words.push(j(6, 8));
    words.push(i(0x13, 0, 20, 20, 1));
    words.push((30 << 7) | 0x17); // auipc x30, 0
    words.push(i(0x13, 0, 30, 30, 16 + i32::from(odd_target)));
    words.push(i(0x67, 0, 7, 30, 0));
    words.push(i(0x13, 0, 20, 20, 1));
}

fn directed(words: &mut Vec<u32>) {
    for (a, value_b) in [(0, 0), (u32::MAX, 1), (0x8000_0000, 31), (0x7fff_ffff, 32)] {
        li(words, 1, a);
        li(words, 2, value_b);
        for funct in 0..8 {
            words.push(r(funct, false, 3, 1, 2));
        }
        words.push(r(0, true, 3, 1, 2));
        words.push(r(5, true, 3, 1, 2));
        for immediate in [-2048, -1, 0, 2047] {
            for funct in [0, 2, 3, 4, 6, 7] {
                words.push(i(0x13, funct, 4, 1, immediate));
            }
        }
        for shamt in [0, 31] {
            words.push(i(0x13, 1, 5, 1, shamt));
            words.push(i(0x13, 5, 5, 1, shamt));
            words.push(i(0x13, 5, 5, 1, 0x400 | shamt));
        }
    }
    // Reserved register fields are ignored, without allocating a writeback tag.
    words.push(i(0x0f, 0, 8, 8, 0));
    words.push(i(0x0f, 1, 8, 8, 0xff));
    // x0 is both an operand and a discarded destination.
    words.push(r(0, false, 0, 1, 2));
    words.push(i(0x13, 0, 8, 0, 0));
    for _ in 0..24 {
        words.push(i(0x13, 0, 8, 8, 1));
    }
    for funct in [0, 1, 4, 5, 6, 7] {
        for (a, value_b) in [(0, 0), (0, 1), (1, 0)] {
            li(words, 1, a);
            li(words, 2, value_b);
            words.push(b(funct, 1, 2, 8));
            words.push(i(0x13, 0, 20, 20, 1));
        }
    }
    // A bounded backwards branch exercises prediction/refetch and repeated PCs.
    words.push(i(0x13, 0, 29, 0, 4));
    words.push(i(0x13, 0, 29, 29, -1));
    words.push(b(1, 29, 0, -4));
    jumps(words, false);
    jumps(words, true);
    for funct in [0, 1, 2] {
        let size = 1 << funct;
        for lane in (0..4).step_by(size) {
            words.push(s(funct, 31, 1, lane));
            words.push(i(0x0f, 0, 0, 0, 0xff));
            words.push(i(0x0f, 1, 0, 0, 0));
            words.push(i(0x03, funct, 9, 31, lane));
            words.push(r(0, false, 10, 9, 2));
            words.push(i(0x03, funct, 0, 31, lane));
            if funct < 2 {
                words.push(i(0x03, funct + 4, 11, 31, lane));
                words.push(i(0x03, funct + 4, 0, 31, lane));
            }
        }
    }
}

pub fn generate(seed: u64, count: usize) -> Result<Program, String> {
    let mut rng = Rng::new(seed ^ 0x6765_6e65_7261_7465);
    let mut words = Vec::new();
    for rd in 1..31 {
        li(&mut words, rd, rng.next_u64() as u32);
    }
    li(&mut words, 31, DATA_START);
    directed(&mut words);
    let end = words.len() + count;
    while words.len() < end {
        let start = words.len();
        let rd = rng.below(29) as u32;
        let rs1 = rng.below(29) as u32;
        let rs2 = rng.below(29) as u32;
        let funct = rng.below(8) as u32;
        match rng.below(12) {
            0..=3 => words.push(r(
                funct,
                (funct == 0 || funct == 5) && rng.bool(),
                rd,
                rs1,
                rs2,
            )),
            4..=5 => {
                let imm = if funct == 1 || funct == 5 {
                    rng.below(32) as i32 | if funct == 5 && rng.bool() { 0x400 } else { 0 }
                } else {
                    rng.below(4096) as i32 - 2048
                };
                words.push(i(0x13, funct, rd, rs1, imm));
            }
            6 => {
                let f = [0, 1, 2, 4, 5][rng.below(5) as usize];
                let size = 1 << (f & 3);
                // Include loads to x0: their missing bus side effects are a DUT
                // failure, never an excuse for the reference model to skip them.
                words.push(i(0x03, f, rd, 31, (rng.below(2048) as i32) & !(size - 1)));
            }
            7 => {
                let f = rng.below(3) as u32;
                words.push(s(f, 31, rs2, (rng.below(2048) as i32) & !((1 << f) - 1)));
            }
            8 => {
                words.push(b([0, 1, 4, 5, 6, 7][rng.below(6) as usize], rs1, rs2, 8));
                words.push(i(0x13, 0, 20, 20, 1));
            }
            9 => jumps(&mut words, rng.bool()),
            10 => words.push(i(0x0f, 0, 0, 0, rng.below(256) as i32)),
            _ => words.push(i(0x0f, 1, 0, 0, 0)),
        }
        // Keep branch/jump blocks intact while honoring the exact image budget.
        // Fill a short tail with independent legal instructions if a block will
        // not fit; never leave a target pointing beyond the terminal instruction.
        if words.len() > end {
            words.truncate(start);
            while words.len() < end {
                words.push(i(0x13, 0, rd, rs1, rng.below(4096) as i32 - 2048));
            }
        }
    }
    finish(words, &mut rng)
}

/// Replay either an exact saved 64 KiB image or a small hexadecimal word list.
pub fn replay(path: &Path, seed: u64) -> Result<Program, String> {
    let raw = fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
    if path.extension().and_then(|s| s.to_str()) == Some("bin") {
        if raw.len() != MEMORY_BYTES {
            return Err("binary replay must be an exact 64 KiB memory.bin".into());
        }
        let mut words = Vec::new();
        for bytes in raw[..DATA_START as usize].as_chunks::<4>().0 {
            let word = u32::from_le_bytes(*bytes);
            words.push(word);
            if word == EBREAK {
                return Ok(Program {
                    terminal_pc: (words.len() as u32 - 1) * 4,
                    words,
                    memory: raw,
                });
            }
        }
        return Err("binary replay has no terminal EBREAK in code memory".into());
    }
    let text = String::from_utf8(raw).map_err(|e| e.to_string())?;
    let mut words = Vec::new();
    for line in text.lines() {
        let code = line.split('#').next().unwrap().trim();
        if code.is_empty() {
            continue;
        }
        words.push(
            u32::from_str_radix(code.trim_start_matches("0x"), 16).map_err(|e| e.to_string())?,
        );
    }
    if words.last() == Some(&EBREAK) {
        words.pop();
    }
    if words.contains(&EBREAK) {
        return Err("hex replay must contain only one terminal EBREAK".into());
    }
    finish(words, &mut Rng::new(seed))
}

pub fn finish(mut words: Vec<u32>, rng: &mut Rng) -> Result<Program, String> {
    let terminal_pc = (words.len() * 4) as u32;
    words.push(EBREAK);
    if words.len() * 4 + 64 >= DATA_START as usize {
        return Err("generated code overlaps data memory".into());
    }
    let mut memory = vec![0; MEMORY_BYTES];
    // Padding is executable NOPs for harmless speculative fetch beyond EBREAK.
    for chunk in memory[..DATA_START as usize].as_chunks_mut::<4>().0 {
        chunk.copy_from_slice(&0x13u32.to_le_bytes());
    }
    for (index, word) in (&words).into_iter().enumerate() {
        memory[index * 4..index * 4 + 4].copy_from_slice(&word.to_le_bytes());
    }
    for byte in &mut memory[DATA_START as usize..DATA_END as usize] {
        *byte = rng.u8();
    }
    Ok(Program {
        words,
        memory,
        terminal_pc,
    })
}
