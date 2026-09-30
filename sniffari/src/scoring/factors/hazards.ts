// Construction is handled as a hard exclusion in rules.ts (exclusionReason) so
// there is exactly one place that decides "never route here". This module is
// the hook for Phase 6 user-reported hazards.
export { exclusionReason } from './rules';
