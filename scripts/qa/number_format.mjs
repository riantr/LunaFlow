// A published number, the way the README writes it: with thousands
// separators.
//
// Two scripts publish byte counts -- the measurement driver that PRINTS the
// README's rows and the checker that COMPARES them -- and they have to agree
// on the spelling, so the spelling lives in one place.  The separators are a
// presentation choice: the number itself is always the measured one, and this
// module never decides what a number should be.
//
// Dependency-free, like the rest of the harness.

export const grouped = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
