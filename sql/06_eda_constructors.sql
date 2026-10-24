-- =====================================================================
-- 06_eda_constructors.sql
-- Exploratory analysis: constructor (team) performance.
-- Note: Ergast treats name changes as separate constructors (Toleman,
-- Benetton, Renault, Alpine are four rows), so totals are per name.
-- =====================================================================

USE f1;

-- ---------------------------------------------------------------------
-- T1. All-time constructor table: wins, podiums and 1-2 finishes.
-- ---------------------------------------------------------------------
WITH per_race AS (
    SELECT constructor_id, constructor_name, race_id, season,
           MAX(is_win)                 AS won,
           SUM(is_podium)              AS podium_cars,
           SUM(finish_position IN (1, 2)) AS cars_in_top2
    FROM v_results
    GROUP BY constructor_id, constructor_name, race_id, season
)
SELECT constructor_name,
       MIN(season)              AS first_season,
       MAX(season)              AS last_season,
       COUNT(*)                 AS races_entered,
       SUM(won)                 AS wins,
       SUM(podium_cars)         AS podiums,
       SUM(cars_in_top2 = 2)    AS one_two_finishes,
       ROUND(100 * SUM(won) / COUNT(*), 1) AS win_pct
FROM per_race
GROUP BY constructor_id, constructor_name
ORDER BY wins DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- T2. Who owned each decade? Share of race wins per constructor.
-- ---------------------------------------------------------------------
WITH decade_wins AS (
    SELECT FLOOR(season / 10) * 10 AS decade, constructor_name,
           COUNT(DISTINCT race_id) AS wins
    FROM v_results
    WHERE is_win = 1 AND is_indy500 = 0
    GROUP BY decade, constructor_id, constructor_name
), ranked AS (
    SELECT decade, constructor_name, wins,
           ROUND(100 * wins / SUM(wins) OVER (PARTITION BY decade), 1) AS share_pct,
           ROW_NUMBER() OVER (PARTITION BY decade ORDER BY wins DESC, constructor_name) AS rn
    FROM decade_wins
)
SELECT decade, constructor_name, wins, share_pct
FROM ranked WHERE rn <= 2
ORDER BY decade, rn;

-- ---------------------------------------------------------------------
-- T3. Most dominant single seasons: share of the season's races won.
-- ---------------------------------------------------------------------
WITH season_races AS (
    SELECT season, COUNT(*) AS races
    FROM races WHERE is_completed = 1 AND is_indy500 = 0
    GROUP BY season
), team_wins AS (
    SELECT season, constructor_name, COUNT(DISTINCT race_id) AS wins
    FROM v_results
    WHERE is_win = 1 AND is_indy500 = 0
    GROUP BY season, constructor_id, constructor_name
)
SELECT t.season, t.constructor_name, t.wins, s.races,
       ROUND(100 * t.wins / s.races, 1) AS win_share_pct
FROM team_wins t JOIN season_races s ON s.season = t.season
ORDER BY win_share_pct DESC
LIMIT 15;

-- ---------------------------------------------------------------------
-- T4. Constructors' champions since the title began in 1958.
-- ---------------------------------------------------------------------
WITH last_round AS (
    SELECT ra.season, MAX(ra.round) AS rnd
    FROM races ra JOIN constructor_standings cs ON cs.race_id = ra.race_id
    GROUP BY ra.season
)
SELECT ra.season, c.constructor_name AS champion, cs.points, cs.wins
FROM constructor_standings cs
JOIN races ra        ON ra.race_id = cs.race_id
JOIN last_round lr   ON lr.season = ra.season AND lr.rnd = ra.round
JOIN constructors c  ON c.constructor_id = cs.constructor_id
WHERE cs.standing_position = 1
ORDER BY ra.season;

-- ---------------------------------------------------------------------
-- T5. Reliability in the hybrid era (2014+): share of starts that ended
--     in a mechanical retirement, for teams with 150+ car starts.
-- ---------------------------------------------------------------------
SELECT constructor_name,
       COUNT(*) AS car_starts,
       SUM(outcome = 'Retired' AND status_category = 'Mechanical')        AS mech_dnfs,
       SUM(outcome = 'Retired' AND status_category = 'Accident / damage') AS crash_dnfs,
       ROUND(100 * SUM(outcome = 'Retired' AND status_category = 'Mechanical') / COUNT(*), 1) AS mech_dnf_pct,
       ROUND(100 * SUM(outcome = 'Classified') / COUNT(*), 1) AS classified_pct
FROM v_results
WHERE season >= 2014 AND started = 1
GROUP BY constructor_id, constructor_name
HAVING car_starts >= 150
ORDER BY mech_dnf_pct;

-- ---------------------------------------------------------------------
-- T6. Pit crew speed (2014+): median stop time per team.
--     Stops over 60 s are red-flag or repair stops and are excluded.
--     MySQL has no MEDIAN(), so the middle row is found with
--     ROW_NUMBER and COUNT windows.
-- ---------------------------------------------------------------------
WITH stops AS (
    SELECT c.constructor_name, ps.duration_ms
    FROM pit_stops ps
    JOIN results r      ON r.race_id = ps.race_id AND r.driver_id = ps.driver_id
    JOIN races ra       ON ra.race_id = ps.race_id
    JOIN constructors c ON c.constructor_id = r.constructor_id
    WHERE ra.season >= 2014 AND ps.duration_ms < 60000
), ordered AS (
    SELECT constructor_name, duration_ms,
           ROW_NUMBER() OVER (PARTITION BY constructor_name ORDER BY duration_ms) AS rn,
           COUNT(*)     OVER (PARTITION BY constructor_name)                      AS n
    FROM stops
)
SELECT constructor_name, MAX(n) AS stops,
       ROUND(AVG(duration_ms) / 1000, 2) AS median_pit_lane_s
FROM ordered
WHERE rn IN (FLOOR((n + 1) / 2), CEIL((n + 1) / 2))
GROUP BY constructor_name
HAVING stops >= 300
ORDER BY median_pit_lane_s;
