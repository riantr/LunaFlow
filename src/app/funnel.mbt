///|
pub struct FunnelResult {
  level1 : Int32
  level2 : Int32
  new_level2 : Array[Finding]
  proved : Int32
  failed : Int32
  unknown : Int32
  critical : Array[String]
  spec_gaps : Array[String]
  abstract_functions : Int32
  abstract_steps : Int32
}

///|
fn same_site(a : Finding, b : Finding) -> Bool {
  a.kind == b.kind &&
  a.file == b.file &&
  a.line == b.line &&
  a.fn_name == b.fn_name
}

///|
pub fn critical_functions(findings : Array[Finding]) -> Array[String] {
  let out : Array[String] = []
  for f in findings {
    if f.fn_name != "" && !out.contains(f.fn_name) {
      out.push(f.fn_name)
    }
  }
  out
}

///|
pub fn funcs_with_contracts(ast : ModuleAst) -> Array[String] {
  let out : Array[String] = []
  for f in ast.all_funcs() {
    if f.contract.has_spec() || f.contract.errors.length() > 0 {
      out.push(f.name)
    }
  }
  out
}

///|
pub fn unique_findings(fs : Array[Finding]) -> Array[Finding] {
  let out : Array[Finding] = []
  for f in fs {
    let mut seen = false
    for x in out {
      if same_site(x, f) {
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
pub fn build_funnel(
  level1_findings : Array[Finding],
  abs : AbsResult,
  proof : ProofResult,
  critical : Array[String],
) -> FunnelResult {
  let uniq1 = unique_findings(level1_findings)
  let new2 : Array[Finding] = []
  for f in abs.findings {
    let mut is_new = true
    for x in uniq1 {
      if same_site(x, f) {
        is_new = false
      }
    }
    if is_new {
      new2.push(f)
    }
  }
  let mut proved = 0
  let mut failed = 0
  let mut unknown = 0
  for vc in proof.vcs {
    match vc.status {
      VCProved => proved = proved + 1
      VCFailed => failed = failed + 1
      VCUnknown => unknown = unknown + 1
    }
  }
  {
    level1: uniq1.length(),
    level2: abs.findings.length(),
    new_level2: new2,
    proved,
    failed,
    unknown,
    critical,
    spec_gaps: proof.spec_gaps,
    abstract_functions: abs.functions,
    abstract_steps: abs.steps,
  }
}
