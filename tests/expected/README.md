# Golden-output fixtures

This directory stores the *expected* output of each award after the canonical
Lahman v2023.1 load. On every CI run, the actual output is `diff`-ed against
these fixtures; any drift is flagged.

Regenerate with:

```bash
make ci         # spin up clean Postgres, load, migrate, test
psql ... -F$'\t' -A -t -f sql/baseball_awards.sql \
    > tests/expected/awards_v2023.1.tsv
```

Files:

| File | Description |
|---|---|
| `awards_v2023.1.tsv` | Top-1 row per award against Lahman v2023.1 |
| `fip_top10_v2023.1.tsv` | Top-10 FIP leaderboard |
| `woba_top10_v2023.1.tsv` | Top-10 wOBA leaderboard |

These are committed so reviewers can see the *answers* in the PR, without
spinning up a Postgres container.
