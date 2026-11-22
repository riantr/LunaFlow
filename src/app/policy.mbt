///|
/// THE UNKNOWN POLICY: what an UNDECIDED claim means, per family.
///
/// A finding carries a VERDICT (`FindingVerdict`): the claim was decided, or
/// it could not be.  The policy turns the second kind into a severity, and
/// the rule is FAIL-CLOSED:
///
///   * an undecided claim about a SAFETY property is an ERROR -- the
///     module's safety is then NOT established, and "we could not decide" is
///     not "it is fine";
///   * an undecided claim about anything else is a WARNING -- it is worth
///     knowing, and it does not by itself say the module is unsafe;
///   * an undecided claim is NEVER merely informational.  `info` is how this
///     project renders the families that never fire, and a claim that could
///     not be decided is not a claim that never applies.
///
/// The policy is a TABLE here rather than a rule scattered over the call
/// sites, so that adding a family is a decision somebody has to make -- the
/// same reason the report's caps live in one place.
///
/// WHY IT MATTERS.  A finding is a CLAIM.  When the analyser could not decide
/// a claim, the old model had nowhere to put that: the finding was absent,
/// and an absent finding is indistinguishable from a decided-and-clean one.
/// The verdict is the difference between "there is nothing here" and "we
/// could not tell", and the policy is what says how loud the second is.
pub fn undecided_severity(kind : FindingKind) -> String {
  if kind.severity() == "error" {
    "error"
  } else {
    "warning"
  }
}

///|
/// The severity a finding CARRIES: its family's severity when the claim was
/// decided, and the POLICY's severity when it was not.
///
/// Every place that renders a severity -- the findings table, the family
/// count table, the sidecar -- goes through here, so the three cannot
/// disagree about how loud a finding is.
pub fn Finding::severity(self : Finding) -> String {
  match self.verdict {
    VerdictCertain => self.kind.severity()
    VerdictUnknown => undecided_severity(self.kind)
  }
}

///|
/// The findings whose claim could NOT be decided, each ONCE.
///
/// The report's findings tables OVERLAP -- a taint finding is in the taint
/// table AND in the L2 table -- and the sidecar's sink holds every copy, so
/// a count taken over the sink has to de-duplicate.  The key carries the
/// VERDICT: a decided finding and an undecided one are different claims
/// about the same site, and the second must not vanish into the first.
pub fn undecided_findings(fs : Array[Finding]) -> Array[Finding] {
  let out : Array[Finding] = []
  for f in fs {
    if f.verdict != VerdictUnknown {
      continue
    }
    let mut seen = false
    for x in out {
      if x.kind == f.kind &&
        x.file == f.file &&
        x.line == f.line &&
        x.message == f.message {
        seen = true
      }
    }
    if !seen {
      out.push(f)
    }
  }
  out
}

///|
/// The number of findings whose claim could NOT be decided.
///
/// This is the count the report publishes, because it is the number that
/// says what the analysis did NOT establish.  A module with zero undecided
/// claims and a module with forty are different things, and only one of them
/// is a clean bill of health.
pub fn count_undecided(fs : Array[Finding]) -> Int32 {
  undecided_findings(fs).length()
}
