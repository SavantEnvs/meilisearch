// KAT (known-answer test) oracle probe for the Meilisearch filter-parser integration.
//
// Drives filter-parser's PUBLIC `FilterCondition::parse` API on FIXED filter strings
// and prints exact, deterministic values. mayhem/test.sh runs this binary and greps the
// exact expected lines (SPEC §6.3 anti-reward-hacking): a PATCH that neuters the parser
// (or this probe) changes/eliminates the output and the oracle FAILS.
//
// Every asserted value is core filter-syntax semantics — equality conditions, numeric
// values, IN-list rendering with AND precedence, the empty-input Ok(None) contract, and
// the reserved-`_geoPoint`-as-value error path — exercised on the very code the `parse`
// fuzz target explores. The Display of a parsed FilterCondition is the crate's own
// canonical rendering used by its snapshot tests, so the expected strings below are
// lifted directly from filter-parser's own `tests` module. No file I/O, no network.
use filter_parser::FilterCondition;

fn disp(s: &str) -> String {
    FilterCondition::parse(s)
        .expect("KAT: filter parse returned Err")
        .expect("KAT: filter parsed to None")
        .to_string()
}

fn main() {
    // KAT1: a simple equality condition.
    println!("KAT1 {}", disp("channel = Ponce")); // KAT1 {channel} = {Ponce}

    // KAT2: a numeric value (still a token, rendered {12}).
    println!("KAT2 {}", disp("subscribers = 12")); // KAT2 {subscribers} = {12}

    // KAT3: IN-list + AND — exercises operator precedence and list rendering.
    println!(
        "KAT3 {}",
        disp(" colour IN [green, blue]  AND color = green ")
    ); // KAT3 AND[{colour} IN[{green}, {blue}, ], {color} = {green}, ]

    // KAT4: the empty filter parses to Ok(None); a reserved `_geoPoint` used as a value
    // is a hard parse error (a neutered parser that "accepts everything" also fails this).
    let empty_is_none = FilterCondition::parse("")
        .expect("KAT4: empty parse returned Err")
        .is_none();
    let geopoint_err = FilterCondition::parse("channel = _geoPoint(12, 13, 14)").is_err();
    println!(
        "KAT4 empty={} geoPointErr={}",
        empty_is_none, geopoint_err
    ); // KAT4 empty=true geoPointErr=true
}
