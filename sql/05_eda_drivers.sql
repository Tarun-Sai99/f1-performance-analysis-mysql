-- =====================================================================
-- 05_eda_drivers.sql
-- Exploratory analysis: driver performance.
-- All queries read from the cleaned layer (v_results and friends).
-- Definitions used throughout:
--   start   = entered the race and took the start (started = 1),
--             counted once per race even for 1950s shared cars
--   win     = classified 1st;  podium = classified 1st to 3rd
--   pole    = started from grid slot 1
-- The 2026 season is in progress (17 of 23 rounds at the data cut-off).
-- =====================================================================

USE f1;

-- ---------------------------------------------------------------------
-- D1. Career summary: the 15 drivers with the most wins.
-- ---------------------------------------------------------------------
WITH career AS (
    SELECT driver_id, driver_name,
           MIN(season)                                      AS first_season,
           MAX(season)                                      AS last_season,
           COUNT(DISTINCT CASE WHEN started = 1 THEN race_id END) AS starts,
           COUNT(DISTINCT CASE WHEN is_win = 1 THEN race_id END)  AS wins,
           COUNT(DISTINCT CASE WHEN is_podium = 1 THEN race_id END) AS podiums,
           COUNT(DISTINCT CASE WHEN is_pole = 1 THEN race_id END) AS poles
    FROM v_results
    GROUP BY driver_id, driver_name
)
SELECT driver_name, first_season, last_season, starts, wins, podiums, poles,
       ROUND(100 * wins / starts, 1)    AS win_pct,
       ROUND(100 * podiums / starts, 1) AS podium_pct
FROM career
ORDER BY wins DESC, podiums DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- D2. Efficiency: highest win rate among drivers with 50+ starts.
--     Raw win totals reward long careers; win rate rewards dominance.
-- ---------------------------------------------------------------------
WITH career AS (
    SELECT driver_name,
           COUNT(DISTINCT CASE WHEN started = 1 THEN race_id END)  AS starts,
           COUNT(DISTINCT CASE WHEN is_win = 1 THEN race_id END)   AS wins,
           COUNT(DISTINCT CASE WHEN is_podium = 1 THEN race_id END) AS podiums
    FROM v_results
    GROUP BY driver_id, driver_name
)
SELECT driver_name, starts, wins,
       ROUND(100 * wins / starts, 1)    AS win_pct,
       ROUND(100 * podiums / starts, 1) AS podium_pct,
       RANK() OVER (ORDER BY wins / starts DESC) AS win_rate_rank
FROM career
WHERE starts >= 50
ORDER BY win_pct DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- D3. Era-neutral scoring: average points per start if every result
--     were scored on today's 25-18-15-12-10-8-6-4-2-1 system.
--     Compares Fangio and Verstappen on the same ruler.
-- ---------------------------------------------------------------------
SELECT driver_name,
       COUNT(DISTINCT race_id)                        AS starts,
       SUM(points_2010_scale)                         AS points_2010_scale,
       ROUND(SUM(points_2010_scale) / COUNT(DISTINCT race_id), 2) AS pts_per_start
FROM v_results
WHERE started = 1 AND is_indy500 = 0
GROUP BY driver_id, driver_name
HAVING starts >= 50
ORDER BY pts_per_start DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- D4. World champions by season, with winning margin.
--     Final standings = standings after the last round of each season.
-- ---------------------------------------------------------------------
WITH last_round AS (
    SELECT ra.season, MAX(ra.round) AS rnd
    FROM races ra JOIN driver_standings ds ON ds.race_id = ra.race_id
    GROUP BY ra.season
), final_table AS (
    SELECT ra.season, ds.driver_id, ds.points, ds.wins, ds.standing_position
    FROM driver_standings ds
    JOIN races ra       ON ra.race_id = ds.race_id
    JOIN last_round lr  ON lr.season = ra.season AND lr.rnd = ra.round
)
SELECT c.season,
       d.full_name AS champion,
       c.points,
       c.wins,
       c.points - r.points                       AS margin_over_p2,
       ROUND(100 * (c.points - r.points) / c.points, 1) AS margin_pct,
       d2.full_name AS runner_up
FROM final_table c
JOIN final_table r ON r.season = c.season AND r.standing_position = 2
JOIN drivers d  ON d.driver_id  = c.driver_id
JOIN drivers d2 ON d2.driver_id = r.driver_id
WHERE c.standing_position = 1
ORDER BY c.season;

-- ---------------------------------------------------------------------
-- D5. Most world titles (completed seasons only, 2026 excluded).
-- ---------------------------------------------------------------------
WITH last_round AS (
    SELECT ra.season, MAX(ra.round) AS rnd
    FROM races ra JOIN driver_standings ds ON ds.race_id = ra.race_id
    GROUP BY ra.season
)
SELECT d.full_name,
       COUNT(*) AS titles,
       GROUP_CONCAT(ra.season ORDER BY ra.season SEPARATOR ', ') AS seasons
FROM driver_standings ds
JOIN races ra      ON ra.race_id = ds.race_id
JOIN last_round lr ON lr.season = ra.season AND lr.rnd = ra.round
JOIN drivers d     ON d.driver_id = ds.driver_id
WHERE ds.standing_position = 1 AND ra.season < 2026
GROUP BY d.driver_id, d.full_name
HAVING titles >= 2
ORDER BY titles DESC, MIN(ra.season);

-- ---------------------------------------------------------------------
-- D6. Consistency in the hybrid era (2014+): average finish and how much
--     it varies, for drivers with 60+ classified finishes. A low standard
--     deviation means the driver lands in a narrow band race after race.
-- ---------------------------------------------------------------------
SELECT driver_name,
       COUNT(*)                               AS classified_finishes,
       ROUND(AVG(finish_position), 2)         AS avg_finish,
       ROUND(STDDEV_SAMP(finish_position), 2) AS sd_finish,
       ROUND(100 * SUM(points_2010_scale > 0) / COUNT(*), 1) AS top10_pct
FROM v_results
WHERE season >= 2014 AND outcome = 'Classified'
GROUP BY driver_id, driver_name
HAVING classified_finishes >= 60
ORDER BY avg_finish
LIMIT 15;

-- ---------------------------------------------------------------------
-- D7. Racecraft: average places gained from grid to flag (2000+,
--     classified finishes with a known grid slot, 80+ races).
--     Caveat: front-row starters cannot gain much, so this favours
--     drivers who often started further back.
-- ---------------------------------------------------------------------
SELECT driver_name,
       COUNT(*)                               AS races,
       ROUND(AVG(grid), 1)                    AS avg_grid,
       ROUND(AVG(finish_position), 1)         AS avg_finish,
       ROUND(AVG(grid - finish_position), 2)  AS avg_places_gained
FROM v_results
WHERE season >= 2000 AND outcome = 'Classified' AND grid IS NOT NULL
GROUP BY driver_id, driver_name
HAVING races >= 80
ORDER BY avg_places_gained DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- D8. Teammate head-to-head (2014+). The fairest driver comparison,
--     since teammates share the same car. Counts races where both
--     teammates were classified and one finished ahead of the other.
-- ---------------------------------------------------------------------
WITH pairs AS (
    SELECT a.driver_id, a.driver_name, b.driver_name AS teammate,
           a.finish_position < b.finish_position AS ahead
    FROM v_results a
    JOIN v_results b
      ON  b.race_id        = a.race_id
      AND b.constructor_id = a.constructor_id
      AND b.driver_id     <> a.driver_id
    WHERE a.season >= 2014
      AND a.outcome = 'Classified' AND b.outcome = 'Classified'
)
SELECT driver_name,
       COUNT(*)                         AS shared_finishes,
       SUM(ahead)                       AS times_ahead,
       ROUND(100 * SUM(ahead) / COUNT(*), 1) AS pct_ahead_of_teammate,
       COUNT(DISTINCT teammate)         AS different_teammates
FROM pairs
GROUP BY driver_id, driver_name
HAVING shared_finishes >= 40
ORDER BY pct_ahead_of_teammate DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- D9. Youngest race winners (age on the day of their first win).
-- ---------------------------------------------------------------------
WITH first_win AS (
    SELECT driver_id, MIN(race_date) AS first_win_date
    FROM v_results WHERE is_win = 1
    GROUP BY driver_id
)
SELECT d.full_name, fw.first_win_date,
       ROUND(DATEDIFF(fw.first_win_date, d.dob) / 365.25, 2) AS age_years
FROM first_win fw JOIN drivers d ON d.driver_id = fw.driver_id
WHERE d.dob IS NOT NULL
ORDER BY age_years
LIMIT 10;
