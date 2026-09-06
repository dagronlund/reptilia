use rustdv::prelude::{Rng, Subscriber};

use crate::{
    bfm::access_memory,
    coverage::CoverageData,
    generation::{b, finish, generate, i, j, li, r, s},
    reference::{ReferenceModel, disassemble},
    scoreboard::{CheckedInstruction, Checker},
    transactions::{Cycle, DATA_START, Decode, Expected, MEMORY_BYTES, MemoryRequest, Writeback},
};

#[test]
fn encodings_match_known_words() {
    assert_eq!(i(0x13, 0, 1, 0, -1), 0xfff00093);
    assert_eq!(r(0, false, 1, 2, 3), 0x003100b3);
    assert_eq!(r(0, true, 1, 2, 3), 0x403100b3);
    assert_eq!(s(2, 2, 1, -4), 0xfe112e23);
    assert_eq!(b(1, 1, 0, -4), 0xfe009ee3);
    assert_eq!(j(1, 8), 0x008000ef);
    assert!(disassemble(0, r(0, true, 1, 2, 3)).contains("sub"));
}

#[test]
fn generation_is_reproducible_and_reference_bounded() {
    for seed in [1, 24301, 0, u64::MAX] {
        let program = generate(seed, 1000).unwrap();
        assert_eq!(
            program.words.len(),
            generate(seed, 0).unwrap().words.len() + 1000
        );
        assert_eq!(program, generate(seed, 1000).unwrap());
        let mut reference = ReferenceModel::new(&program);
        let mut count = 0;
        while reference.hart.pc != program.terminal_pc {
            reference.step().unwrap();
            count += 1;
            assert!(count < 10000);
        }
        assert!(count > 1000);
    }
    assert_ne!(
        generate(1, 10).unwrap().words,
        generate(2, 10).unwrap().words
    );
}

#[test]
fn directed_reference_closes_required_coverage() {
    let program = generate(1, 0).unwrap();
    let mut reference = ReferenceModel::new(&program);
    let mut coverage = CoverageData::default();
    let mut tags = [0u8; 32];
    while reference.hart.pc != program.terminal_pc {
        let expected = reference.step().unwrap();
        let tag = expected
            .write
            .map(|(rd, _)| {
                let n = tags[rd as usize];
                tags[rd as usize] = (n + 1) & 7;
                n
            })
            .unwrap_or(0);
        coverage.write(&CheckedInstruction { expected, tag });
    }
    assert_eq!(coverage.missing(), Vec::<String>::new());
}

fn expected(pc: u32, rd: u8, value: u32) -> Expected {
    Expected {
        pc,
        instruction: i(0x13, 0, rd as u32, 0, value as i32),
        next_pc: pc + 4,
        write: Some((rd, value)),
        memory: None,
        operands: [0; 2],
    }
}
fn issue(checker: &mut Checker, expected: &Expected, tag: u8) {
    checker
        .accept(
            Decode {
                pc: expected.pc,
                instruction: expected.instruction,
                tag,
                execute: true,
                flushed: false,
            },
            Some(expected),
            10000,
        )
        .unwrap();
}
fn wb(rd: u8, tag: u8, value: u32) -> Writeback {
    Writeback {
        rd,
        tag,
        value,
        killed: false,
        writes: true,
    }
}

#[test]
fn writes_can_reorder_between_registers_but_not_within_one() {
    let mut checker = Checker::default();
    issue(&mut checker, &expected(0, 1, 10), 0);
    issue(&mut checker, &expected(4, 2, 20), 0);
    checker.writeback(wb(2, 0, 20)).unwrap();
    assert!(checker.writeback(wb(1, 0, 11)).is_err());
    checker.writeback(wb(1, 0, 10)).unwrap();
    assert!(checker.writeback(wb(1, 0, 10)).is_err());
    issue(&mut checker, &expected(8, 1, 30), 1);
    issue(&mut checker, &expected(12, 1, 40), 2);
    assert!(checker.writeback(wb(1, 2, 40)).is_err());
    checker.writeback(wb(1, 1, 30)).unwrap();
    checker.writeback(wb(1, 2, 40)).unwrap();
}

#[test]
fn tags_wrap_without_accepting_stale_writes() {
    let mut checker = Checker::default();
    for n in 0..40 {
        issue(&mut checker, &expected(n * 4, 1, n), (n & 7) as u8);
        checker.writeback(wb(1, (n & 7) as u8, n)).unwrap();
    }
    assert!(checker.writeback(wb(1, 7, 39)).is_err());
}

#[test]
fn independent_memory_and_signed_loads() {
    let mut words = Vec::new();
    li(&mut words, 1, DATA_START);
    li(&mut words, 2, 0x80ff);
    words.push(s(1, 1, 2, 2));
    words.push(i(0x03, 0, 3, 1, 3));
    words.push(i(0x03, 4, 4, 1, 3));
    let program = finish(words, &mut Rng::new(1)).unwrap();
    let original = program.memory.clone();
    let mut reference = ReferenceModel::new(&program);
    while reference.hart.pc != program.terminal_pc {
        reference.step().unwrap();
    }
    assert_eq!(reference.hart.registers[3], 0xffff_ff80);
    assert_eq!(reference.hart.registers[4], 0x80);
    assert_eq!(program.memory, original);
    let mut memory = vec![0; MEMORY_BYTES];
    let request = MemoryRequest {
        address: DATA_START + 2,
        data: 0x80ff0000,
        mask: 12,
        ..MemoryRequest::default()
    };
    access_memory(&mut memory, 1, request).unwrap();
    assert_eq!(
        &memory[DATA_START as usize..DATA_START as usize + 4],
        &[0, 0, 255, 128]
    );
    assert!(access_memory(&mut memory, 0, request).is_err());
}

#[test]
fn checker_cannot_pass_empty_missing_or_killed_work() {
    let mut checker = Checker::default();
    assert!(checker.finish(&[0; 32], &[], &[]).is_err());
    issue(&mut checker, &expected(0, 1, 1), 0);
    assert!(!checker.drained());
    let mut write = wb(1, 0, 1);
    write.killed = true;
    assert!(checker.writeback(write).is_err());
    assert!(checker.memory(MemoryRequest::default()).is_err());
}

#[test]
fn load_x0_requires_memory_access_without_register_write() {
    let program = generate(1, 0).unwrap();
    let mut reference = ReferenceModel::new(&program);
    let load = loop {
        assert_ne!(
            reference.hart.pc, program.terminal_pc,
            "directed image must exercise loads to x0"
        );
        let expected = reference.step().unwrap();
        if expected.write.is_none() && expected.memory.as_ref().is_some_and(|access| access.read) {
            break expected;
        }
    };
    assert_eq!(load.write, None);
    assert_eq!(load.memory.as_ref().unwrap().address, DATA_START);
    assert_eq!(reference.hart.registers[0], 0);
    let decode = Decode {
        pc: load.pc,
        instruction: load.instruction,
        tag: 0,
        execute: false,
        flushed: false,
    };
    let mut checker = Checker::default();
    assert!(
        checker
            .accept(decode, Some(&load), program.terminal_pc)
            .is_err()
    );
    checker
        .accept(
            Decode {
                execute: true,
                ..decode
            },
            Some(&load),
            program.terminal_pc,
        )
        .unwrap();
    let request = MemoryRequest {
        read: true,
        address: DATA_START,
        mask: 0,
        ..MemoryRequest::default()
    };
    assert!(
        checker
            .memory(MemoryRequest {
                address: DATA_START + 4,
                ..request
            })
            .is_err()
    );
    checker.memory(request).unwrap();
    assert!(checker.memory(request).is_err());
}

#[test]
fn samples_reject_reordering_and_flushed_dispatch() {
    let mut checker = Checker::default();
    let frame = Cycle {
        number: 1,
        ..Cycle::default()
    };
    checker.observe(&frame, None, 100).unwrap();
    assert!(checker.observe(&frame, None, 100).is_err());
    assert!(
        checker
            .observe(
                &Cycle {
                    number: 2,
                    error: true,
                    ..frame
                },
                None,
                100
            )
            .is_err()
    );
    let decode = Decode {
        pc: 0,
        instruction: 0x13,
        tag: 0,
        execute: false,
        flushed: true,
    };
    checker.accept(decode, None, 100).unwrap();
    assert_eq!(checker.flushed, 1);
    assert!(
        checker
            .accept(
                Decode {
                    execute: true,
                    ..decode
                },
                None,
                100
            )
            .is_err()
    );
}

#[test]
fn fences_preserve_registers_and_memory() {
    let program = finish(
        vec![
            i(0x13, 0, 8, 0, 123),
            i(0x0f, 0, 8, 8, 0xff),
            i(0x0f, 1, 8, 8, 0xff),
            i(0x13, 0, 9, 8, 1),
        ],
        &mut Rng::new(1),
    )
    .unwrap();
    let mut reference = ReferenceModel::new(&program);
    reference.step().unwrap();
    for pc in [4, 8] {
        let expected = reference.step().unwrap();
        assert_eq!(expected.pc, pc);
        assert_eq!(expected.next_pc, pc + 4);
        assert_eq!(expected.write, None);
        assert_eq!(expected.memory, None);
        assert_eq!(reference.hart.registers[8], 123);
        assert_eq!(reference.memory.bytes, program.memory);
    }
    assert_eq!(reference.step().unwrap().write, Some((9, 124)));
}
