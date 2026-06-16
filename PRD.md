Here is your updated Product Requirements Document based on your exact structure guidelines.

The file below is prepared as if it were being saved to `/tasks/prd-baseball-analytics-database.md`.

---

# prd-baseball-analytics-database.md

## Introduction/Overview

The Best of Baseball Analytics Database is an educational and analytical database project designed to help developers interact with a massive relational dataset containing historical baseball records from 1871 to 2019.

A common issue when working with historical datasets is that raw data is often overwhelming, dense, and difficult to extract immediate value from due to changes in industry metrics over time (such as inflation or structural shift variations). This feature introduces an analytical workflow inside a PostgreSQL database GUI client to extract deep performance insights, efficiency metrics, and physical trends through targeted, highly optimized relational queries.

## Goals

* Provide a clear schema verification workflow using a graphical user interface (GUI) client like Postbird.
* Create highly performant query scripts that evaluate large-scale multi-table joins without performance degradation.
* Calculate 6 core historical awards based on mathematical aggregations, expenditure ratios, and specific metadata parameters.

## User Stories

* As a sports analyst, I want to join player physical attributes with their historical team assignments so that I can discover whether physical traits like height or weight correlate with specific eras of team success.
* As a team general manager, I want to compute total player salaries relative to seasonal team wins so that I can measure financial performance metrics and pinpoint high-efficiency rosters.
* As a junior database developer, I want to run performance-optimized scripts using explicit join paths so that I can see the real-world impact of execution engine plans on large legacy datasets.

## Functional Requirements

1. **Database Schema Ingestion:** The system must support the execution and streaming of the baseline legacy structural file (`baseball_database.sql`) directly via a GUI client import interface to build and populate all 29 relational tables.
2. **Physical Metric Aggregations:**
* **Requirement 2.1 (Heaviest Hitters):** The system must compute the historical team profile (grouped by `team_id` and `year_id`) that presents the maximum average player weight by joining the `people` and `batting` tables.
* **Requirement 2.2 (Shortest Sluggers):** The system must compute the historical team profile that presents the minimum average player height by reusing the relational grouping architecture established in Requirement 2.1.


3. **Financial Matrix Computations:**
* **Requirement 3.1 (Biggest Spenders):** The system must scan and aggregate total compensation data within the `salaries` table to calculate the single maximum seasonal payroll allocation in baseball history.
* **Requirement 3.2 (Most Bang For Their Buck):** The system must calculate seasonal roster financial efficiency exclusively for the target year 2010. The system must isolate the team with the lowest cost-per-win ratio using the mathematical formula:

$$\text{Cost Per Win} = \frac{\sum(\text{salaries.salary})}{\text{teams.w}}$$




4. **Outlier Threshold Analysis (Priciest Starter):** The system must identify the single pitcher in any given year who cost the most money per game started ($\frac{\text{salary}}{\text{pitching.gs}}$). The script must apply a strict data constraint filter to only include pitchers who recorded a minimum of 10 games started (`pitching.gs >= 10`).
5. **Custom Core Metric Generation ("Canadian Ace"):** The system must isolate performance trends within Canadian boundaries by finding the single pitcher across all historical data who maintained the lowest Earned Run Average (`pitching.era`) while actively contracted to a Canadian franchise (filtering specifically for team identifiers `TOR` or `MON`).
6. **Query Plan Execution Monitoring:** Every analytical query block must include query plan inspection syntax (`EXPLAIN ANALYZE`) preceding the statement to force the PostgreSQL engine to output concrete execution paths, scan choices, and index utilization statistics.

## Non-Goals (Out of Scope)

* Constructing user-facing web dashboards, graphical charts, or frontend application layers.
* Handling programmatic edge-case validation scripts for missing database inputs or `NULL` modifications (the baseline dataset is assumed to be structurally sound and clean).
* Creating new manual indexing structures or altering the core table relationships provided in the source `.sql` file.

## Design Considerations

* **GUI Navigation Layout:** Junior developers should rely on the visual features of their client tool (e.g., Postbird) to inspect structural components.
* Developers must use the **Structure Tab** to verify structural data column bindings and primary keys, and use the **Content Tab** for immediate manual scanning of small subsets of row values.
* Custom analytics code must be developed, tested, and stored sequentially inside the client’s raw **Query Tab** interface.

## Technical Considerations

* **Execution Environment Constraints:** Relational joins are performed against dense tables containing millions of historical items. Writing cross-joins or running unindexed full-table scans will dramatically increase query latency.
* **Join Paths:** To ensure correct row pairing without creating unintended Cartesian products, queries tracking team-wide payroll allocations or efficiency metrics must map structural equality parameters explicitly across both `team_id` and `year_id` constraints simultaneously:
```sql
FROM salaries
INNER JOIN teams 
  ON salaries.team_id = teams.team_id 
 AND salaries.year_id = teams.year_id

```


* **Data Typings:** Calculations involving payroll summation patterns must accurately accommodate large-scale numbers using standard aggregate functions without overflowing memory spaces.

## Success Metrics

* 100% processing rate of the base database ingestion file into a local database instance without terminal connection dropping or structural execution crash failures.
* Retrieval of exact, singular target names and structural row records for each of the 6 defined award parameters within an execution timeline under 250ms per query statement.
* Visible output log confirmation of the structural query execution maps (`EXPLAIN ANALYZE`) inside the client console log for tracking execution health.

## Open Questions

* Are there any historical instances where a team changed its standard identifier abbreviation halfway through a single calendar year, and if so, should those records be aggregated under a unified corporate franchise index?
* Will future updates to the dataset expand beyond the current historical window bounds (1871–2019), and do the current aggregation math patterns scale cleanly if data parameters scale exponentially?