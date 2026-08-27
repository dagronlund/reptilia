# Repository Instructions

Run lint checks with:

```sh
uvx ruff check .
cargo check
cargo clippy
```

Run after rust changes:
```sh
cargo fmt
cargo test
```

Run after systemverilog changes:
```sh
uv run ./main.py --format
uv run ./main.py --rustdv-tests --dhrystone
```

# Rust Code Style

- Avoid using .iter(), always use .into_iter() (with borrowing if necessary) instead
- Within reason, leverage traits for multiple functions that implement similar behavior
- Avoid using matches!() and instead use == (just a matter of personal preference, fallback on a match statement if needed)
- Avoid named functions inside of other functions (just put them outside, its way less indenting), closures are fine to put inside other functions of course
- Always "use std::..." at the top, followed by a separate block for libraries, and then finally a single nested use statement for "use crate::{...}"
- Avoid `crate::something::MyStruct` when not in a use statement
- Avoid `pub use ...`
- Put `mod ...` before any `use ...`
- Avoid `use super::..`, instead write `use crate::...`
