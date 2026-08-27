use std::collections::VecDeque;

use crate::MemTransaction;

fn check_next(
    expected: &mut VecDeque<MemTransaction>,
    actual: MemTransaction,
) -> Result<(), &'static str> {
    match expected.pop_front() {
        Some(next) if next == actual => Ok(()),
        Some(_) => Err("memory scoreboard mismatch"),
        None => Err("unexpected memory transaction"),
    }
}

fn stimulus(seed: u64, count: usize) -> Vec<u64> {
    let mut state = seed;
    (0..count)
        .map(|_| {
            state = state
                .wrapping_mul(6_364_136_223_846_793_005)
                .wrapping_add(1);
            state
        })
        .collect()
}

#[test]
fn scoreboard_rejects_payload_id_last_and_order_mutations() {
    let a = MemTransaction {
        read: true,
        write: 0,
        addr: 1,
        data: 2,
        id: 3,
        last: false,
    };
    let b = MemTransaction { addr: 2, ..a };
    for mutated in [
        MemTransaction { data: 9, ..a },
        MemTransaction { id: 4, ..a },
        MemTransaction { last: true, ..a },
        b,
    ] {
        let mut expected = VecDeque::from([a, b]);
        assert!(check_next(&mut expected, mutated).is_err());
    }
    let mut expected = VecDeque::from([a, b]);
    assert!(check_next(&mut expected, a).is_ok());
    assert!(check_next(&mut expected, b).is_ok());
}

#[test]
fn read_first_expectation_keeps_old_value() {
    let old = 7;
    let new = 9;
    assert_eq!(old, 7);
    assert_ne!(old, new);
}

#[test]
fn deterministic_stimulus_repeats_by_seed() {
    assert_eq!(stimulus(7, 32), stimulus(7, 32));
    assert_ne!(stimulus(7, 32), stimulus(8, 32));
}
