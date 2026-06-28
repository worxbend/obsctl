1. Repair the local contract fixture gap and add manifest completeness
   validation.
2. Enforce the main Crystal validation gates in CI.
3. Add obsctl doctor with human and JSON output.
4. Implement recording controls as the first larger OBS Studio feature slice.
5. Add obsctl watch --json once the event stream contract is specified.

## Agent Loop Tasks

The strict implementation queue for resumable agent iterations is maintained in
.agent-loop/tasks.json. All tasks start as pending.

1. T001 Canonicalize legacy contract fixtures.
2. T002 Validate contract manifest structure.
3. T003 Prove fixture manifest completeness.
4. T004 Run contract repair checkpoint.
5. T005 Add main Crystal CI gate.
6. T006 Make lint behavior explicit.
7. T007 Run CI gate checkpoint.
8. T008 Strengthen CLI boundary regressions.
9. T009 Add doctor config diagnostics.
10. T010 Extend doctor runtime checks.
11. T011 Freeze doctor JSON contracts.
12. T012 Run doctor checkpoint.
13. T013 Implement config explain.
14. T014 Implement config diff.
15. T015 Implement config migrate.
16. T016 Run config-helper checkpoint.
17. T017 Add recording OBS primitives.
18. T018 Wire record command path.
19. T019 Freeze record CLI contracts.
20. T020 Run recording checkpoint.
21. T021 Add streaming controls.
22. T022 Add replay buffer controls.
23. T023 Add virtual camera controls.
24. T024 Run stream-output checkpoint.
25. T025 Add scene and source operations.
26. T026 Add transition and collection controls.
27. T027 Add scriptable watch stream.
28. T028 Add macro command sequences.
29. T029 Run final validation gate.

## Build Gates

For every Crystal change:

make format
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build
make lint

