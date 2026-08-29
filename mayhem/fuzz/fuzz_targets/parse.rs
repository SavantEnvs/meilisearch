// Additive in-process libFuzzer harness for the Meilisearch filter-parser.
//
// A 1:1 port of upstream's own harness (crates/filter-parser/fuzz/fuzz_targets/parse.rs):
// feed the fuzzer bytes as UTF-8, cap the length to avoid the well-known deep-recursion
// stack overflow that only reproduces under the fuzzer, and parse the Meilisearch filter
// syntax. An `InternalError` from the parser is a real defect (the parser must return a
// user-facing error or succeed, never an internal error), so we panic on it — that is
// the invariant we fuzz for. No disk I/O; upstream source is untouched — this crate only
// CALLS the unmodified filter_parser library.
#![no_main]
use filter_parser::{ErrorKind, FilterCondition};
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if let Ok(s) = std::str::from_utf8(data) {
        // When we are fuzzing the parser we can get a stack overflow very easily.
        // But since this doesn't happen with a normal build we are just going to limit
        // the fuzzer to 500 characters.
        if s.len() < 500 {
            match FilterCondition::parse(s) {
                Err(e) if matches!(e.kind(), ErrorKind::InternalError(_)) => {
                    panic!("Found an internal error: `{:?}`", e)
                }
                _ => (),
            }
        }
    }
});
