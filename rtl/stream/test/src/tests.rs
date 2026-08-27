use std::{collections::VecDeque, mem};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct Beat {
    payload: u32,
    source: u8,
    last: bool,
}

fn check_next(expected: &mut VecDeque<Beat>, actual: Beat) -> Result<(), &'static str> {
    match expected.pop_front() {
        Some(next) if next == actual => Ok(()),
        Some(_) => Err("stream scoreboard mismatch"),
        None => Err("unexpected stream beat"),
    }
}

fn round_robin_order(mut pending: [VecDeque<u32>; 2]) -> Vec<u32> {
    let mut selected = 0;
    let mut output = Vec::new();
    while (&pending).into_iter().any(|queue| !queue.is_empty()) {
        for offset in 0..2 {
            let source = (selected + offset) % 2;
            if let Some(value) = pending[source].pop_front() {
                output.push(value);
                selected = (source + 1) % 2;
                break;
            }
        }
    }
    output
}

fn packets(beats: &[Beat]) -> Vec<Vec<Beat>> {
    let mut result = Vec::new();
    let mut packet = Vec::new();
    for beat in beats {
        packet.push(*beat);
        if beat.last {
            result.push(mem::take(&mut packet));
        }
    }
    assert!(packet.is_empty(), "unterminated packet");
    result
}

fn stimulus(seed: u64, count: usize) -> Vec<u64> {
    let mut state = seed;
    (0..count)
        .map(|_| {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        })
        .collect()
}

#[test]
fn packet_grouping_respects_last() {
    let beats = (0..12)
        .map(|payload| Beat {
            payload,
            source: 0,
            last: (payload + 1) % 4 == 0,
        })
        .collect::<Vec<_>>();
    assert_eq!(
        packets(&beats)
            .into_iter()
            .map(|packet| packet.len())
            .collect::<Vec<_>>(),
        [4, 4, 4]
    );
}

#[test]
fn scoreboard_rejects_payload_source_last_and_order_mutations() {
    let a = Beat {
        payload: 10,
        source: 0,
        last: false,
    };
    let b = Beat {
        payload: 11,
        source: 0,
        last: true,
    };
    for mutated in [
        Beat { payload: 99, ..a },
        Beat { source: 1, ..a },
        Beat { last: true, ..a },
        b,
    ] {
        let mut expected = VecDeque::from([a, b]);
        assert!(check_next(&mut expected, mutated).is_err());
    }
}

#[test]
fn arbitration_prediction_is_round_robin() {
    assert_eq!(
        round_robin_order([VecDeque::from([0, 2, 4]), VecDeque::from([1, 3, 5])]),
        [0, 1, 2, 3, 4, 5]
    );
}

#[test]
fn deterministic_stimulus_repeats_by_seed() {
    assert_eq!(stimulus(7, 32), stimulus(7, 32));
    assert_ne!(stimulus(7, 32), stimulus(8, 32));
}
