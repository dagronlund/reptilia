use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    rc::Rc,
};

use rustdv::prelude::*;

use crate::{
    bfm::Session,
    generation::{OPERATIONS, operation},
    scoreboard::CheckedInstruction,
};

#[derive(Default, Debug)]
pub struct CoverageData {
    pub operations: BTreeMap<String, usize>,
    pub branches: BTreeSet<(String, bool)>,
    pub lanes: BTreeSet<(String, u32)>,
    pub edges: BTreeSet<u32>,
    pub dependencies: BTreeSet<String>,
    pub crosses: BTreeSet<(String, String)>,
    previous: Option<(u8, bool)>,
    previous_tags: BTreeMap<u8, u8>,
}

impl Subscriber<CheckedInstruction> for CoverageData {
    fn write(&mut self, item: &CheckedInstruction) {
        let e = &item.expected;
        let name = operation(e.instruction).to_string();
        *self.operations.entry(name.clone()).or_default() += 1;
        let opcode = e.instruction & 127;
        if opcode == 0x63 {
            self.branches.insert((name.clone(), e.next_pc != e.pc + 4));
        }
        if let Some(memory) = &e.memory {
            self.lanes.insert((name.clone(), memory.address & 3));
        }
        let rs1 = (e.instruction >> 15) & 31;
        let rs2 = (e.instruction >> 20) & 31;
        let uses_rs1 = opcode == 0x33
            || opcode == 0x13
            || opcode == 0x03
            || opcode == 0x23
            || opcode == 0x63
            || opcode == 0x67;
        let uses_rs2 = opcode == 0x33 || opcode == 0x23 || opcode == 0x63;
        for (used, reg, value) in [
            (uses_rs1, rs1, e.operands[0]),
            (uses_rs2, rs2, e.operands[1]),
        ] {
            if !used {
                continue;
            }
            if [0, 1, u32::MAX, 0x8000_0000, 0x7fff_ffff, 31, 32].contains(&value) {
                self.edges.insert(value);
            }
            if reg == 0 {
                self.dependencies.insert("x0 source".into());
            }
            let category = if value == 0 {
                "zero"
            } else if (value as i32) < 0 {
                "negative"
            } else {
                "positive"
            };
            self.crosses.insert((name.clone(), category.to_string()));
            if let Some((rd, load)) = self.previous
                && reg == rd as u32
            {
                self.dependencies
                    .insert(if load { "load use" } else { "forwarding" }.into());
            }
        }
        if let Some((rd, _)) = e.write {
            if self.previous.map(|p| p.0) == Some(rd) {
                self.dependencies.insert("repeated destination".into());
            }
            if self.previous_tags.get(&rd) == Some(&7) && item.tag == 0 {
                self.dependencies.insert("tag wrap".into());
            }
            self.previous_tags.insert(rd, item.tag);
            self.previous = Some((rd, opcode == 0x03));
        } else {
            self.previous = None;
        }
    }
}

impl CoverageData {
    pub fn missing(&self) -> Vec<String> {
        let mut missing = Vec::new();
        for op in OPERATIONS {
            if !self.operations.contains_key(op) {
                missing.push(format!("operation {op}"));
            }
        }
        for op in ["beq", "bne", "blt", "bge", "bltu", "bgeu"] {
            for taken in [false, true] {
                if !self.branches.contains(&(op.into(), taken)) {
                    missing.push(format!("{op} taken={taken}"));
                }
            }
        }
        for (op, step) in [
            ("lb", 1),
            ("lbu", 1),
            ("lh", 2),
            ("lhu", 2),
            ("lw", 4),
            ("sb", 1),
            ("sh", 2),
            ("sw", 4),
        ] {
            for lane in (0..4).step_by(step) {
                if !self.lanes.contains(&(op.into(), lane)) {
                    missing.push(format!("{op} lane {lane}"));
                }
            }
        }
        for value in [0, 1, u32::MAX, 0x8000_0000, 0x7fff_ffff, 31, 32] {
            if !self.edges.contains(&value) {
                missing.push(format!("operand {value:#x}"));
            }
        }
        for name in [
            "x0 source",
            "load use",
            "forwarding",
            "repeated destination",
            "tag wrap",
        ] {
            if !self.dependencies.contains(name) {
                missing.push(name.into());
            }
        }
        missing
    }
}

#[derive(Component, Default)]
pub struct Coverage {
    #[port(subscribe)]
    checked: SubscribePort<CheckedInstruction>,
    data: RustdvShared<CoverageData>,
}
impl Component for Coverage {
    fn build(&mut self, _: &mut RustdvCtx) {
        self.checked.subscribe(self.data.clone());
    }
    fn check(&mut self, ctx: &mut RustdvCtx, errors: &mut CheckSink) {
        let session: Rc<Session> = ConfigDb::get(Some(ctx), "", "SESSION").expect("session");
        if session.failed.is_set() {
            return;
        }
        if session.config.replay.is_some() {
            ctx.info(
                "focused replay: reporting coverage without requiring the full directed suite",
            );
            return;
        }
        for missing in self.data.get().missing() {
            errors.error(format!("coverage missing: {missing}"));
        }
    }
    fn report(&mut self, ctx: &mut RustdvCtx) {
        let session: Rc<Session> = ConfigDb::get(Some(ctx), "", "SESSION").expect("session");
        let text = format!(
            "{:#?}\nMissing required bins: {:?}\n",
            self.data.get(),
            self.data.get().missing()
        );
        if let Err(error) = fs::write(session.config.artifacts.join("coverage.txt"), text) {
            ctx.error(&format!("could not write coverage artifact: {error}"));
        }
        ctx.info(&format!(
            "checked coverage: {:?}; operand crosses={}; dependencies={:?}",
            self.data.get().operations,
            self.data.get().crosses.len(),
            self.data.get().dependencies
        ));
    }
}
