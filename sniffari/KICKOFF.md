Paste this into Claude Code as your first message (start in Plan Mode — Shift+Tab until it says plan mode):

---

Read CLAUDE.md and docs/SPEC.md fully. We're doing Phase 0 only.

Give me:
1. The proposed file tree
2. TypeScript type definitions for Node, Edge, EdgeFeatures, FactorResult, Profile, Route, Destination, and WalkRequest
3. The public interface of each module (function signatures, one line each on what they do)
4. The exact Overpass QL query you'll use for the fixture area, and roughly how big the response will be for a 1.5-mile radius
5. How you'll structure the Web Worker boundary (what goes in, what comes out, progress events)
6. Anything in the spec you think is wrong, underspecified, or will be a problem in practice — push back where you disagree

Don't write implementation code yet. Stop when the plan is done and wait for my go-ahead on Phase 1.
