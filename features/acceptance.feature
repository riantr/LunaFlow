# language: en
Feature: LunaFlow acceptance runs
  The analyzer is judged on artefacts it produces, not on intent. These
  scenarios restate the quantified acceptance criteria from docs/design.md
  section 10.2 as executable behaviour.

  Scenario: The fixture exposes the pinned static and dynamic findings
    Given the built CLI binary
    When I analyze the demo fixture with the funnel and a slice
    Then the run exits successfully
    Then the summary reports 3 dead code findings
    And the summary reports 1 unreachable statement
    And the summary reports at least 1 infinite loop
    And the summary reports at least 1 taint sink
    And the summary reports at least 1 abstract finding
    And at least 1 contract is proved and at least 1 fails

  Scenario: The report is a complete, renderable document
    Given the built CLI binary
    When I analyze the demo fixture with the funnel and a slice
    Then the report has all ten sections
    And the report contains a funnel diagram
    And the report contains a valid slice diagram
    And the report stays under 512 KB

  Scenario: Two identical runs produce identical artefacts
    Given the built CLI binary
    When I analyze the demo fixture twice into the same directory
    Then the two summaries are identical except the elapsed time
    And the two traces are byte identical

  Scenario: A hostile module cannot exhaust the parser stack
    Given the built CLI binary
    When I analyze a module with 5000 nested if statements
    Then the run exits successfully
    Then the report records a parse gap
    And the summary does not claim the skipped region as understood code

  Scenario: A hostile module cannot write outside the report directory
    Given the built CLI binary
    When I analyze a module whose version field tries to escape the output directory
    Then the run exits successfully
    Then no artifact is written outside the output directory

  Scenario: A malformed command line never writes into the working directory
    Given the built CLI binary
    When I pass --out with no value
    Then the run exits successfully
    And no artifact is written into the working directory

  Scenario: The toolchain gates stay green
    Given the project working tree
    Then the source tree is canonically formatted
    Then the unit suite passes
    Then the acceptance verifier passes
