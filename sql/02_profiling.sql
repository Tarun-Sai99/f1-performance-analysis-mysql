-- =====================================================================
-- 02_profiling.sql
-- Data quality audit of the raw layer, run BEFORE cleaning.
-- Each block answers one question about the raw data. The findings are
-- summarised in the README and each one maps to a fix in 03_cleaning.sql.
-- =====================================================================

USE f1;

-- ---------------------------------------------------------------------
-- P1. How many literal '\N' null markers does each key table contain?
-- ---------------------------------------------------------------------
SELECT 'results' AS tbl,
       SUM(number = '\\N')         AS number_nulls,
       SUM(grid = '\\N')           AS grid_nulls,
       SUM(position = '\\N')       AS position_nulls,
       SUM(time = '\\N')           AS time_nulls,
       SUM(milliseconds = '\\N')   AS ms_nulls,
       SUM(fastestLapTime = '\\N') AS fastest_lap_nulls,
       COUNT(*)                    AS total_rows
FROM raw_results;

SELECT 'drivers' AS tbl,
       SUM(number = '\\N')      AS number_nulls,
       SUM(code = '\\N')        AS code_nulls,
       SUM(dob = '\\N')         AS dob_nulls,
       SUM(nationality = '\\N') AS nationality_nulls,
       SUM(url = '\\N')         AS url_nulls,
       COUNT(*)                 AS total_rows
FROM raw_drivers;

SELECT 'qualifying' AS tbl,
       SUM(q1 = '\\N') AS q1_nulls,
       SUM(q2 = '\\N') AS q2_nulls,
       SUM(q3 = '\\N') AS q3_nulls,
       COUNT(*)        AS total_rows
FROM raw_qualifying;

-- ---------------------------------------------------------------------
-- P2. Do numeric columns contain anything that is not a number?
-- ---------------------------------------------------------------------
SELECT 'results.points' AS col, COUNT(*) AS non_numeric
FROM raw_results WHERE points NOT REGEXP '^[0-9]+(\\.[0-9]+)?$'
UNION ALL
SELECT 'results.grid', COUNT(*) FROM raw_results WHERE grid NOT REGEXP '^[0-9]+$'
UNION ALL
SELECT 'results.position', COUNT(*) FROM raw_results WHERE position NOT REGEXP '^[0-9]+$'
UNION ALL
SELECT 'results.laps', COUNT(*) FROM raw_results WHERE laps NOT REGEXP '^[0-9]+$';

-- ---------------------------------------------------------------------
-- P3. The 'time' column mixes two meanings: the winner's total race
--     time ('1:34:50.616') and gaps to the winner ('+5.478', '+1 Lap').
-- ---------------------------------------------------------------------
SELECT CASE
         WHEN time = '\\N'                     THEN 'null marker'
         WHEN time REGEXP '^[0-9]+:[0-9]{2}:[0-9]{2}\\.[0-9]+$' THEN 'total race time h:mm:ss'
         WHEN time REGEXP '^[0-9]+:[0-9]{2}\\.[0-9]+$'          THEN 'total race time m:ss (short race)'
         WHEN time LIKE '+%Lap%'                THEN 'gap in laps'
         WHEN time LIKE '+%'                    THEN 'gap in time'
         ELSE 'other'
       END AS time_format,
       COUNT(*) AS n
FROM raw_results
GROUP BY time_format
ORDER BY n DESC;

-- ---------------------------------------------------------------------
-- P4. grid = 0 means "started from the pit lane" (or unknown in the
--     early years), not pole position. It must not be treated as P0.
-- ---------------------------------------------------------------------
SELECT grid = '0' AS grid_is_zero, COUNT(*) AS n
FROM raw_results GROUP BY grid_is_zero;

-- ---------------------------------------------------------------------
-- P5. positionText codes: numbers are classified finishers, letters
--     are R=retired, D=disqualified, E=excluded, W=withdrew,
--     F=failed to qualify, N=not classified.
-- ---------------------------------------------------------------------
SELECT CASE WHEN positionText REGEXP '^[0-9]+$' THEN 'numeric (classified)'
            ELSE positionText END AS position_text,
       COUNT(*) AS n
FROM raw_results GROUP BY position_text ORDER BY n DESC;

-- ---------------------------------------------------------------------
-- P6. 143 free-text status values. Too granular to analyse directly,
--     so they will be grouped into categories.
-- ---------------------------------------------------------------------
SELECT s.status, COUNT(*) AS n
FROM raw_results r JOIN raw_status s ON s.statusId = r.statusId
GROUP BY s.status ORDER BY n DESC LIMIT 25;

-- ---------------------------------------------------------------------
-- P7. Duplicates.
--     a) exact duplicate result rows
--     b) same driver twice in one race (shared drives in the 1950s,
--        where two drivers split one car, or one driver ran two cars)
-- ---------------------------------------------------------------------
SELECT COUNT(*) - COUNT(DISTINCT resultId) AS duplicate_result_ids FROM raw_results;

SELECT r.raceId, ra.year, ra.name, r.driverId, COUNT(*) AS entries
FROM raw_results r JOIN raw_races ra ON ra.raceId = r.raceId
GROUP BY r.raceId, ra.year, ra.name, r.driverId
HAVING COUNT(*) > 1
ORDER BY ra.year LIMIT 10;

SELECT COUNT(*) AS driver_race_pairs_with_multiple_entries FROM (
  SELECT raceId, driverId FROM raw_results
  GROUP BY raceId, driverId HAVING COUNT(*) > 1) t;

-- ---------------------------------------------------------------------
-- P8. Inconsistent text values: whitespace and spelling variants.
-- ---------------------------------------------------------------------
SELECT nationality, CONCAT('[', nationality, ']') AS bracketed, COUNT(*) AS n
FROM raw_drivers
WHERE nationality <> TRIM(nationality) OR nationality LIKE 'Argentin%'
GROUP BY nationality;

-- ---------------------------------------------------------------------
-- P9. Placeholder rows: drivers in the file who have never entered a
--     race, qualifying session or sprint (2026 reserve/test drivers with
--     no date of birth or nationality).
-- ---------------------------------------------------------------------
SELECT d.driverId, d.forename, d.surname, d.dob, d.nationality
FROM raw_drivers d
WHERE NOT EXISTS (SELECT 1 FROM raw_results r WHERE r.driverId = d.driverId)
  AND NOT EXISTS (SELECT 1 FROM raw_qualifying q WHERE q.driverId = d.driverId)
  AND NOT EXISTS (SELECT 1 FROM raw_sprint_results s WHERE s.driverId = d.driverId);

-- ---------------------------------------------------------------------
-- P10. Scheduled races that have not happened yet (no results).
-- ---------------------------------------------------------------------
SELECT ra.year, COUNT(*) AS races_without_results, MIN(ra.date) AS first_date
FROM raw_races ra
WHERE NOT EXISTS (SELECT 1 FROM raw_results r WHERE r.raceId = ra.raceId)
GROUP BY ra.year;

-- ---------------------------------------------------------------------
-- P11. Referential integrity: results pointing at missing parents.
-- ---------------------------------------------------------------------
SELECT
  SUM(NOT EXISTS (SELECT 1 FROM raw_races x WHERE x.raceId = r.raceId))                     AS missing_race,
  SUM(NOT EXISTS (SELECT 1 FROM raw_drivers x WHERE x.driverId = r.driverId))               AS missing_driver,
  SUM(NOT EXISTS (SELECT 1 FROM raw_constructors x WHERE x.constructorId = r.constructorId)) AS missing_constructor,
  SUM(NOT EXISTS (SELECT 1 FROM raw_status x WHERE x.statusId = r.statusId))                 AS missing_status
FROM raw_results r;

-- ---------------------------------------------------------------------
-- P12. Points systems changed many times (8 pts for a win in 1950,
--      10 from 1991, 25 from 2010), so raw points are not comparable
--      across eras.
-- ---------------------------------------------------------------------
SELECT ra.year, MAX(CAST(r.points AS DECIMAL(5,2))) AS max_points_one_race
FROM raw_results r JOIN raw_races ra ON ra.raceId = r.raceId
WHERE ra.year IN (1950, 1960, 1980, 1991, 2003, 2010, 2014, 2019, 2025)
GROUP BY ra.year ORDER BY ra.year;

-- ---------------------------------------------------------------------
-- P13. Lap time strings ('1:27.452') need converting to milliseconds.
--      Check that every non-null value matches m:ss.sss.
-- ---------------------------------------------------------------------
SELECT 'qualifying.q1' AS col, COUNT(*) AS bad_format
FROM raw_qualifying WHERE q1 <> '\\N' AND q1 NOT REGEXP '^[0-9]+:[0-9]{2}\\.[0-9]{3}$'
UNION ALL
SELECT 'results.fastestLapTime', COUNT(*)
FROM raw_results WHERE fastestLapTime <> '\\N' AND fastestLapTime NOT REGEXP '^[0-9]+:[0-9]{2}\\.[0-9]{3}$';

-- ---------------------------------------------------------------------
-- P14. Do position and positionText agree?
--      a) classified (numeric positionText) but position is '\N'
--      b) not classified (R/W/D...) but position is filled in. This
--         starts in 2025: the newer source fills position for every car,
--         so position alone can no longer tell you who finished.
-- ---------------------------------------------------------------------
SELECT r.resultId, ra.year, ra.name, r.positionText, r.position, r.positionOrder
FROM raw_results r JOIN raw_races ra ON ra.raceId = r.raceId
WHERE r.positionText REGEXP '^[0-9]+$' AND r.position = '\\N';

SELECT 'results' AS tbl, ra.year, COUNT(*) AS unclassified_with_position
FROM raw_results r JOIN raw_races ra ON ra.raceId = r.raceId
WHERE r.positionText NOT REGEXP '^[0-9]+$' AND r.position <> '\\N'
GROUP BY ra.year
UNION ALL
SELECT 'sprint_results', ra.year, COUNT(*)
FROM raw_sprint_results s JOIN raw_races ra ON ra.raceId = s.raceId
WHERE s.positionText NOT REGEXP '^[0-9]+$' AND s.position <> '\\N'
GROUP BY ra.year;

-- ---------------------------------------------------------------------
-- P15. Sprint results with no status at all.
-- ---------------------------------------------------------------------
SELECT s.resultId, ra.year, ra.name, s.position, s.positionText, s.statusId
FROM raw_sprint_results s JOIN raw_races ra ON ra.raceId = s.raceId
WHERE s.statusId = '\\N';

-- ---------------------------------------------------------------------
-- P16. Impossible qualifying laps: more than 1.5x the fastest q1 time
--      in the same session.
-- ---------------------------------------------------------------------
SELECT ra.year, ra.name, d.surname, q.q1,
       ROUND(q.q1_s / q.fastest_q1_s, 2) AS times_slower_than_fastest
FROM (
    SELECT raceId, driverId, q1, q1_s,
           MIN(q1_s) OVER (PARTITION BY raceId) AS fastest_q1_s
    FROM (
        SELECT raceId, driverId, q1,
               CAST(SUBSTRING_INDEX(q1, ':', 1) AS UNSIGNED) * 60
                 + CAST(SUBSTRING_INDEX(q1, ':', -1) AS DECIMAL(6,3)) AS q1_s
        FROM raw_qualifying WHERE q1 <> '\\N'
    ) t
) q
JOIN raw_races ra  ON ra.raceId  = q.raceId
JOIN raw_drivers d ON d.driverId = q.driverId
WHERE q.q1_s > 1.5 * q.fastest_q1_s;
