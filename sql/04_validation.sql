-- =====================================================================
-- 04_validation.sql
-- Checks run AFTER cleaning. Every query should return the "expected"
-- value noted above it. Saved output: outputs/04_validation_output.txt
-- =====================================================================

USE f1;

-- V1. Row counts: raw vs clean. Only drivers should differ (-16 placeholders).
SELECT 'drivers' AS tbl, (SELECT COUNT(*) FROM raw_drivers) AS raw_rows, (SELECT COUNT(*) FROM drivers) AS clean_rows
UNION ALL SELECT 'constructors', (SELECT COUNT(*) FROM raw_constructors), (SELECT COUNT(*) FROM constructors)
UNION ALL SELECT 'circuits', (SELECT COUNT(*) FROM raw_circuits), (SELECT COUNT(*) FROM circuits)
UNION ALL SELECT 'races', (SELECT COUNT(*) FROM raw_races), (SELECT COUNT(*) FROM races)
UNION ALL SELECT 'results', (SELECT COUNT(*) FROM raw_results), (SELECT COUNT(*) FROM results)
UNION ALL SELECT 'sprint_results', (SELECT COUNT(*) FROM raw_sprint_results), (SELECT COUNT(*) FROM sprint_results)
UNION ALL SELECT 'qualifying', (SELECT COUNT(*) FROM raw_qualifying), (SELECT COUNT(*) FROM qualifying)
UNION ALL SELECT 'driver_standings', (SELECT COUNT(*) FROM raw_driver_standings), (SELECT COUNT(*) FROM driver_standings)
UNION ALL SELECT 'constructor_standings', (SELECT COUNT(*) FROM raw_constructor_standings), (SELECT COUNT(*) FROM constructor_standings)
UNION ALL SELECT 'pit_stops', (SELECT COUNT(*) FROM raw_pit_stops), (SELECT COUNT(*) FROM pit_stops);

-- V2. No literal '\N' text left in any cleaned text column. Expected: 0.
SELECT (SELECT COUNT(*) FROM drivers WHERE code = '\\N' OR nationality = '\\N')
     + (SELECT COUNT(*) FROM circuits WHERE location = '\\N' OR country = '\\N')
     + (SELECT COUNT(*) FROM constructors WHERE nationality = '\\N') AS leftover_null_markers;

-- V3. No untrimmed or variant nationalities. Expected: 0 rows.
SELECT nationality, COUNT(*) FROM drivers
WHERE nationality <> TRIM(nationality) OR nationality = 'Argentinian'
GROUP BY nationality;

-- V4. Every completed race has exactly one winner. Expected: 0 rows.
--     (1950s shared drives can put two drivers in one car, so they are
--     checked separately below.)
SELECT ra.season, ra.race_name, SUM(r.finish_position = 1) AS winners
FROM races ra JOIN results r ON r.race_id = ra.race_id
WHERE ra.is_completed = 1
GROUP BY ra.race_id, ra.season, ra.race_name
HAVING winners <> 1 AND ra.season > 1960;

SELECT ra.season, ra.race_name, SUM(r.finish_position = 1) AS winners
FROM races ra JOIN results r ON r.race_id = ra.race_id
GROUP BY ra.race_id, ra.season, ra.race_name
HAVING winners > 1;

-- V5. Only future races lack results. Expected: one row, 2026, 6 races.
SELECT season, COUNT(*) AS not_completed FROM races WHERE is_completed = 0 GROUP BY season;

-- V6. Grid and position ranges are sensible. Expected: grid 1..~34,
--     no zero grids, finish positions start at 1.
SELECT MIN(grid) AS min_grid, MAX(grid) AS max_grid,
       SUM(grid = 0) AS zero_grids,
       MIN(finish_position) AS min_pos, MAX(finish_position) AS max_pos
FROM results;

-- V7. Outcome matches status where it should. A disqualified outcome
--     should never be paired with status 'Finished'. Expected: 0.
SELECT COUNT(*) AS dsq_but_finished
FROM v_results WHERE outcome = 'Disqualified' AND status = 'Finished';

-- V8. Points reconcile with the official championship table.
--     From 1991 every result counted (no "best N results" rule), so
--     race + sprint points per driver per season must equal the final
--     standings. Expected: 0 rows.
WITH last_round AS (
    SELECT ra.season, MAX(ra.round) AS rnd
    FROM races ra JOIN driver_standings ds ON ds.race_id = ra.race_id
    GROUP BY ra.season
), final_table AS (
    SELECT ra.season, ds.driver_id, ds.points
    FROM driver_standings ds
    JOIN races ra ON ra.race_id = ds.race_id
    JOIN last_round lr ON lr.season = ra.season AND lr.rnd = ra.round
), earned AS (
    SELECT season, driver_id, SUM(pts) AS points
    FROM (
        SELECT ra.season, r.driver_id, r.points AS pts
        FROM results r JOIN races ra ON ra.race_id = r.race_id
        UNION ALL
        SELECT ra.season, s.driver_id, s.points
        FROM sprint_results s JOIN races ra ON ra.race_id = s.race_id
    ) x
    GROUP BY season, driver_id
)
SELECT f.season, d.full_name, f.points AS standings_points, e.points AS summed_points
FROM final_table f
JOIN earned e  ON e.season = f.season AND e.driver_id = f.driver_id
JOIN drivers d ON d.driver_id = f.driver_id
WHERE f.season >= 1991 AND f.points <> e.points
ORDER BY f.season;

-- V9. Qualifying times are in a believable range (50s to 3 min).
SELECT MIN(best_lap_ms) / 1000 AS fastest_s, MAX(best_lap_ms) / 1000 AS slowest_s,
       SUM(best_lap_ms IS NULL) AS no_time_set
FROM qualifying;

-- V10. Foreign keys exist on the fact tables.
SELECT TABLE_NAME, COUNT(*) AS foreign_keys
FROM information_schema.REFERENTIAL_CONSTRAINTS
WHERE CONSTRAINT_SCHEMA = 'f1'
GROUP BY TABLE_NAME ORDER BY TABLE_NAME;
