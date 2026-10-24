-- =====================================================================
-- 07_eda_race_dynamics.sql
-- Exploratory analysis: how races are won and lost across eras.
-- Eras: 1950-1979, 1980-1999, 2000-2013, 2014-present (hybrid).
-- Indianapolis 500 (part of the championship 1950-1960, but a different
-- series in practice) is excluded from these race-level comparisons.
-- =====================================================================

USE f1;

-- ---------------------------------------------------------------------
-- R1. Pole-to-win conversion by era: how often does the pole sitter win?
-- ---------------------------------------------------------------------
SELECT era,
       COUNT(*)                         AS races_with_known_pole,
       SUM(is_win)                      AS pole_sitter_won,
       ROUND(100 * SUM(is_win) / COUNT(*), 1) AS pole_to_win_pct
FROM v_results
WHERE is_pole = 1 AND is_indy500 = 0
GROUP BY era
ORDER BY era;

-- ---------------------------------------------------------------------
-- R2. Where do winners start? Win share by grid slot, hybrid era vs all.
-- ---------------------------------------------------------------------
SELECT CASE WHEN grid IS NULL THEN 'Pit lane / unknown'
            WHEN grid <= 5   THEN CONCAT('P', grid)
            WHEN grid <= 10  THEN 'P6-P10'
            ELSE 'P11+' END                            AS start_slot,
       COUNT(*)                                        AS wins_all_time,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_all_time,
       SUM(season >= 2014)                             AS wins_hybrid,
       ROUND(100 * SUM(season >= 2014) / SUM(SUM(season >= 2014)) OVER (), 1) AS pct_hybrid
FROM v_results
WHERE is_win = 1 AND is_indy500 = 0
GROUP BY start_slot
ORDER BY MIN(COALESCE(grid, 99));

-- ---------------------------------------------------------------------
-- R3. Reliability over time: % of starters who retired, by decade,
--     split into mechanical failures and accidents.
-- ---------------------------------------------------------------------
SELECT FLOOR(season / 10) * 10 AS decade,
       COUNT(*)                AS starts,
       ROUND(100 * SUM(outcome = 'Retired') / COUNT(*), 1) AS dnf_pct,
       ROUND(100 * SUM(outcome = 'Retired' AND status_category = 'Mechanical') / COUNT(*), 1) AS mechanical_pct,
       ROUND(100 * SUM(outcome = 'Retired' AND status_category = 'Accident / damage') / COUNT(*), 1) AS accident_pct,
       ROUND(100 * SUM(outcome = 'Retired' AND status_category NOT IN ('Mechanical', 'Accident / damage')) / COUNT(*), 1) AS other_pct
FROM v_results
WHERE started = 1 AND is_indy500 = 0
GROUP BY decade
ORDER BY decade;

-- ---------------------------------------------------------------------
-- R4. Field size and finishers per race by decade.
-- ---------------------------------------------------------------------
WITH per_race AS (
    SELECT race_id, FLOOR(MIN(season) / 10) * 10 AS decade,
           COUNT(*)                   AS entries,
           SUM(started)               AS starters,
           SUM(outcome = 'Classified') AS classified
    FROM v_results WHERE is_indy500 = 0
    GROUP BY race_id
)
SELECT decade, COUNT(*) AS races,
       ROUND(AVG(entries), 1)    AS avg_entries,
       ROUND(AVG(starters), 1)   AS avg_starters,
       ROUND(AVG(classified), 1) AS avg_classified,
       ROUND(100 * AVG(classified / starters), 1) AS pct_starters_classified
FROM per_race
GROUP BY decade ORDER BY decade;

-- ---------------------------------------------------------------------
-- R5. Circuits where qualifying matters most (2000+, 10+ races):
--     how often the pole sitter won there.
-- ---------------------------------------------------------------------
SELECT ci.circuit_name, ci.country,
       COUNT(*)                         AS races,
       SUM(v.is_win)                    AS pole_wins,
       ROUND(100 * SUM(v.is_win) / COUNT(*), 1) AS pole_to_win_pct
FROM v_results v
JOIN races ra    ON ra.race_id = v.race_id
JOIN circuits ci ON ci.circuit_id = ra.circuit_id
WHERE v.is_pole = 1 AND v.season >= 2000
GROUP BY ci.circuit_id, ci.circuit_name, ci.country
HAVING races >= 10
ORDER BY pole_to_win_pct DESC;

-- ---------------------------------------------------------------------
-- R6. Competitiveness: how many different drivers and teams won each
--     season (more winners = a more open championship).
-- ---------------------------------------------------------------------
SELECT season,
       COUNT(DISTINCT race_id)          AS races,
       COUNT(DISTINCT driver_id)        AS different_winning_drivers,
       COUNT(DISTINCT constructor_id)   AS different_winning_teams
FROM v_results
WHERE is_win = 1 AND is_indy500 = 0
GROUP BY season
ORDER BY season;

-- ---------------------------------------------------------------------
-- R7. Year-over-year change in the champion team's win count, using LAG.
--     Shows how quickly dominant periods start and end (2000+).
-- ---------------------------------------------------------------------
WITH team_season AS (
    SELECT season, constructor_name, COUNT(DISTINCT race_id) AS wins
    FROM v_results
    WHERE is_win = 1
    GROUP BY season, constructor_id, constructor_name
), top_team AS (
    SELECT season, constructor_name, wins,
           ROW_NUMBER() OVER (PARTITION BY season ORDER BY wins DESC, constructor_name) AS rn
    FROM team_season
)
SELECT season, constructor_name AS most_wins, wins,
       LAG(constructor_name) OVER (ORDER BY season) AS prev_season_leader,
       wins - LAG(wins) OVER (ORDER BY season)      AS change_vs_prev_leader
FROM top_team
WHERE rn = 1 AND season >= 2000
ORDER BY season;
