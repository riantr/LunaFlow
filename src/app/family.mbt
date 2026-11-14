///|
/// THE FINDING FAMILIES: the kinds of finding this analyzer can report,
/// addressed by the CODE the report already prints.
///
/// The peer analyzer addresses its families by a stable id (`MSA-007`). The
/// analogue here is the code, so the vocabulary a reader has seen in a report
/// is the vocabulary they type. The rule that makes that safe is the peer's
/// own: **a code is never renamed.** A new kind of finding gets a NEW code,
/// and every code keeps the meaning it was published with.
///
/// Two rules govern a profile, and they are the peer's:
///
///   * a code that names NO family is a WARNING, and the scan still runs. The
///     reader asked for a scan, and a profile that silently ignored an
///     unknown code would read as "that family has no findings", which is a
///     very different claim from "that family is not this version's".
///   * a code that is BOTH included and excluded is an ERROR, and the scan
///     does not run at all. The two rules contradict each other, so no
///     reading of the profile satisfies both.

///|
/// Every family, in report order.
///
/// The last ten are the EVOLVED VALUE ANALYSIS families: the defect classes a
/// value analysis can reach once it stops being a range tracker and starts
/// asking what the value is USED FOR. Four of them are RESERVED — the classes
/// MoonBit's type system makes impossible in safe code — and their contracts
/// say so, so `--explain` can answer for them instead of staying silent.
pub fn family_roster() -> Array[FindingKind] {
  [
    FDead,
    FUnreachable,
    FInfinite,
    FTaintIndex,
    FTaintIndexRange,
    FTaintAlloc,
    FRangeViolation,
    FParseGap,
    FBudget,
    FUnsupported,
    FIntOverflow,
    FDivZero,
    FIndexOob,
    FNoneDeref,
    FUninitRead,
    FInvalidCast,
    FUseAfterFree,
    FPointerArithmetic,
    FMemoryLeak,
    FFormatString,
  ]
}

///|
/// The families the EVOLVED VALUE ANALYSIS produces.
///
/// A family is in this list when the analysis has a check behind it. The
/// RESERVED families are NOT in this list: they are in the roster so that
/// `--explain` can answer for them, and they never fire.
pub fn eva_families() -> Array[FindingKind] {
  [FIntOverflow, FDivZero, FIndexOob, FNoneDeref, FUninitRead, FInvalidCast]
}

///|
/// The family with this code, or None when the code names no family.
pub fn family_by_code(code : String) -> FindingKind? {
  for k in family_roster() {
    if k.code() == code {
      return Some(k)
    }
  }
  None
}

///|
/// A short human title, in the peer's "name" slot.
pub fn family_title(kind : FindingKind) -> String {
  match kind {
    FDead => "DeadCode"
    FUnreachable => "Unreachable"
    FInfinite => "InfiniteLoop"
    FTaintIndex => "TaintedIndex"
    FTaintIndexRange => "TaintedIndexInRange"
    FTaintAlloc => "TaintedAllocation"
    FRangeViolation => "RangeViolation"
    FParseGap => "ParseGap"
    FBudget => "BudgetExceeded"
    FUnsupported => "UnsupportedSink"
    FIntOverflow => "IntegerOverflow"
    FDivZero => "DivisionByZero"
    FIndexOob => "IndexOutOfBounds"
    FNoneDeref => "NoneDereference"
    FUninitRead => "UninitializedRead"
    FInvalidCast => "InvalidCast"
    FUseAfterFree => "UseAfterFree"
    FPointerArithmetic => "PointerArithmetic"
    FMemoryLeak => "MemoryLeak"
    FFormatString => "FormatString"
  }
}

///|
/// The property the family asserts: one line, no hedging.
pub fn family_property(kind : FindingKind) -> String {
  match kind {
    FDead => "a statement is unreachable after an unconditional exit"
    FUnreachable =>
      "no execution reaches this statement: the flow arriving at it has already left the block"
    FInfinite =>
      "the loop cannot terminate: its condition holds for every input and it has no break"
    FTaintIndex => "a tainted value may reach an array index or a buffer offset"
    FTaintIndexRange =>
      "a tainted value reaches an index that is in range on every observed path"
    FTaintAlloc => "a tainted value may control an allocation size"
    FRangeViolation =>
      "a value's range may be violated: an assertion may fail, or a size may be negative"
    FParseGap =>
      "a construct the frontend could not model, folded into the statement it belongs to"
    FBudget =>
      "an analysis budget was exhausted, so the rest of the function was not analysed"
    FUnsupported => "a tainted value may reach abort/panic"
    FIntOverflow =>
      "an integer operation may leave the range of its type: MoonBit wraps silently, so the value is wrong rather than a crash"
    FDivZero =>
      "a division or a modulo may divide by zero, which the runtime turns into a panic"
    FIndexOob =>
      "an index may fall outside the array it addresses, in either direction"
    FNoneDeref =>
      "an Option may be None where it is unwrapped, which the runtime turns into a panic"
    FUninitRead =>
      "an element of an uninitialized array may be read before it is written, so the value read is indeterminate"
    FInvalidCast =>
      "a conversion may not be representable in the target type, and the runtime saturates it silently"
    FUseAfterFree =>
      "a value may be used after the storage it referred to was released"
    FPointerArithmetic =>
      "pointer arithmetic may leave the bounds of the object it addresses"
    FMemoryLeak => "storage may be allocated and never released"
    FFormatString =>
      "an attacker-controlled string may be interpreted as a format string"
  }
}

///|
/// The assumption under which the property is sound.
pub fn family_assumption(kind : FindingKind) -> String {
  match kind {
    FDead =>
      "the CFG saw every branch of the function body, and the parser modelled every construct in it"
    FUnreachable =>
      "the CFG is complete for the function, and the abstract input set at L2 was not empty"
    FInfinite =>
      "the condition was modelled as a constant, or as true over the whole abstract input set"
    FTaintIndex =>
      "the taint source set was complete, and the sink was reached on an observed path"
    FTaintIndexRange =>
      "every path the interpreter executed was observed, and the array's length was known"
    FTaintAlloc =>
      "the allocation's size argument was read from the tainted value"
    FRangeViolation =>
      "the abstract range of the value was sound for the inputs it was computed from"
    FParseGap =>
      "the fold did not change the meaning of the surrounding statement"
    FBudget =>
      "the budget was large enough for the function up to the point it ran out"
    FUnsupported =>
      "the abort was read as a sink, and the tainted value reached it"
    FIntOverflow =>
      "the operand types were known, or the operation was on the default 32-bit Int type; MoonBit's integer arithmetic wraps rather than trapping, so this is a SILENT wrong value"
    FDivZero =>
      "the divisor's interval is the abstract one, so a zero inside it is a real possibility"
    FIndexOob =>
      "the array's length and the index's interval are both known, so the comparison is over the whole input abstraction"
    FNoneDeref =>
      "the Option's None-ness was tracked from the branches that produce it, and the unwrap is on a value the analysis could not prove to be Some"
    FUninitRead =>
      "the writes to the array were tracked, and the index read is not one of them"
    FInvalidCast =>
      "the source value's interval was known, and it leaves the target type's range"
    FUseAfterFree =>
      "NOT APPLICABLE IN MOONBIT: safe MoonBit has no raw pointers, the collector owns the storage, and values are immutable -- there is nothing to free and nothing to dangle"
    FPointerArithmetic =>
      "NOT APPLICABLE IN MOONBIT: there is no pointer type in safe MoonBit, so there is no pointer arithmetic to be illegal"
    FMemoryLeak =>
      "NOT APPLICABLE IN MOONBIT: the collector reclaims unreachable storage and there is no manual free, so storage cannot leak"
    FFormatString =>
      "NOT APPLICABLE IN MOONBIT: there are no format strings. The language interpolates with a typed syntax and the core has no printf-style formatting, so no string is ever interpreted as a format"
  }
}

///|
/// What the family does NOT cover.
pub fn family_excluded(kind : FindingKind) -> String {
  match kind {
    FDead =>
      "a statement the parser folded into its parent, and a function whose body was not parsed at all"
    FUnreachable =>
      "a branch the parser could not model, and a path the interpreter never executed"
    FInfinite =>
      "a loop whose condition the parser did not model, and a loop with a break the parser did not see"
    FTaintIndex =>
      "an index the runtime clamps, and a value the source model did not mark tainted"
    FTaintIndexRange =>
      "a path the trials did not synthesise, and an array whose length is unknown"
    FTaintAlloc =>
      "a size the runtime clamps, and a value the source model did not mark tainted"
    FRangeViolation =>
      "a range the abstract interpreter could not compute, and an assertion in a function that was not interpreted"
    FParseGap =>
      "nothing -- and note the kind is RESERVED: the gaps are counted as 'Statements unsupported' in the report's ingestion table rather than reported as findings"
    FBudget => "everything after the budget ran out"
    FUnsupported =>
      "a panic the parser did not model, and a tainted value that never reached it"
    FIntOverflow =>
      "64-bit operands: the abstract domain's integer interval is 32-bit wide, so a 64-bit operation is NOT checked -- the check is stated for the default Int type and for operands whose type is known"
    FDivZero =>
      "a divisor whose interval could not be computed, and a floating-point division, where a zero divisor is an infinity rather than a panic"
    FIndexOob =>
      "an array whose length is not known -- a fixed-size array with an unknown size, and any array read through a pointer-like value"
    FNoneDeref =>
      "an Option that the analysis proved to be Some, and a Result, whose failure is a different family"
    FUninitRead =>
      "an element written on every path before the read, and an element written inside a loop, whose index set the analysis cannot bound"
    FInvalidCast =>
      "a conversion between integer types, which MoonBit makes explicit and total, and a narrowing between trait objects"
    FUseAfterFree =>
      "nothing -- and note the kind is RESERVED: safe MoonBit cannot express the defect"
    FPointerArithmetic =>
      "nothing -- and note the kind is RESERVED: safe MoonBit cannot express the defect"
    FMemoryLeak =>
      "nothing -- and note the kind is RESERVED: safe MoonBit cannot express the defect. The nearest real exhaustion is unbounded growth in a collection, which this analyzer does not measure"
    FFormatString =>
      "nothing -- and note the kind is RESERVED: safe MoonBit cannot express the defect"
  }
}

///|
/// The whole roster, in the peer's `--explain-all` shape.
pub fn explain_roster() -> String {
  let out = StringBuilder::new()
  out.write_string(
    "families: code, title, and the property each one asserts\n\n",
  )
  for k in family_roster() {
    out.write_string(
      "  " +
      k.code() +
      "  " +
      family_title(k) +
      "  --  " +
      family_property(k) +
      "\n",
    )
  }
  out.write_string(
    "\n--explain <code> prints one family's full contract: what it asserts, the assumption under which that is sound, and what it does not cover.\n",
  )
  out.to_string()
}

///|
/// One family's full contract, or the message the peer prints for an unknown
/// id.
pub fn explain_family(code : String) -> String {
  match family_by_code(code) {
    None =>
      "ERROR\tno family has the code \"" +
      code +
      "\"; the roster is " +
      family_codes().join(", ") +
      "\n"
    Some(k) => {
      let out = StringBuilder::new()
      out.write_string(k.code() + "  " + family_title(k) + "\n\n")
      out.write_string("  property    " + family_property(k) + "\n\n")
      out.write_string("  assumption  " + family_assumption(k) + "\n\n")
      out.write_string("  excluded    " + family_excluded(k) + "\n")
      out.to_string()
    }
  }
}

///|
/// Every family code, in roster order.
pub fn family_codes() -> Array[String] {
  let out : Array[String] = []
  for k in family_roster() {
    out.push(k.code())
  }
  out
}

///|
/// Check a profile against the roster.
///
/// The return is (warnings, error). An empty error means the profile is
/// usable.
pub fn validate_profile(
  include_codes : Array[String],
  exclude_codes : Array[String],
) -> (Array[String], String) {
  let warnings : Array[String] = []
  let roster = family_codes().join(", ")
  for c in include_codes {
    if family_by_code(c) is None {
      warnings.push(
        "unknown family code in --families: " +
        c +
        " (the roster is " +
        roster +
        ")",
      )
    }
  }
  for c in exclude_codes {
    if family_by_code(c) is None {
      warnings.push(
        "unknown family code in --exclude-families: " +
        c +
        " (the roster is " +
        roster +
        ")",
      )
    }
  }
  let overlap : Array[String] = []
  for c in include_codes {
    if exclude_codes.contains(c) {
      overlap.push(c)
    }
  }
  if overlap.length() > 0 {
    return (
      warnings,
      "the profile includes and excludes the same family code: " +
      overlap.join(", "),
    )
  }
  (warnings, "")
}

///|
/// Does this profile keep the family?
///
/// The include set is applied FIRST and the exclude set SECOND, and the order
/// is not a preference: a code in both is an ERROR (see `validate_profile`),
/// so the two sets never meet here and the order cannot change the answer.
pub fn profile_keeps(
  kind : FindingKind,
  include_codes : Array[String],
  exclude_codes : Array[String],
) -> Bool {
  let code = kind.code()
  if include_codes.length() > 0 && !include_codes.contains(code) {
    return false
  }
  if exclude_codes.contains(code) {
    return false
  }
  true
}

///|
/// The findings a profile keeps.
///
/// The filter is by CODE and it is applied to the WHOLE finding list, so the
/// counts in the summary describe the SAME set of findings the report shows.
/// A filter applied after the counts would leave `dead_code` counting
/// findings the reader can never see, and the summary's identity would stop
/// adding up.
pub fn filter_findings(
  findings : Array[Finding],
  include_codes : Array[String],
  exclude_codes : Array[String],
) -> Array[Finding] {
  let kept : Array[Finding] = []
  for f in findings {
    if profile_keeps(f.kind, include_codes, exclude_codes) {
      kept.push(f)
    }
  }
  kept
}

///|
/// Split a profile argument into codes. Commas and spaces both separate, so
/// `--families A,B` and `--families A B` mean the same thing.
pub fn split_codes(s : String) -> Array[String] {
  let out : Array[String] = []
  for part in s.split(",").to_array() {
    for word in part.split(" ").to_array() {
      let w = word.trim().to_owned()
      if w != "" {
        out.push(w)
      }
    }
  }
  out
}
