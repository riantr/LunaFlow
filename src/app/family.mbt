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
  ]
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
