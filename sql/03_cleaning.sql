-- =====================================================================
-- 03_cleaning.sql
-- Builds typed, cleaned tables from the raw_* staging tables.
--
-- Cleaning steps (numbers match the README):
--   C1  Convert literal '\N' markers to real NULLs
--   C2  Cast text to proper types (INT, DECIMAL, DATE, TIME)
--   C3  Trim whitespace and standardise spelling variants
--   C4  Convert lap/qualifying time strings to milliseconds
--   C5  Treat grid = 0 as "no grid slot" (NULL) plus a pit-lane flag
--   C6  Decode positionText into a single outcome column and fix rows
--       where position and positionText disagree
--   C7  Group 143 free-text status values into categories
--   C8  Remove placeholder drivers who never took part in any session
--   C9  Flag races that have not been run yet (future 2026 rounds)
--   C10 Add era-neutral points (2010+ 25-18-15 scale) for fair comparison
--   C11 Add primary and foreign keys so bad references cannot creep in
--   C12 Null out impossible qualifying laps (more than 1.5x pole time)
-- =====================================================================

USE f1;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- circuits
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS circuits;
CREATE TABLE circuits (
    circuit_id   INT          PRIMARY KEY,
    circuit_ref  VARCHAR(50)  NOT NULL,
    circuit_name VARCHAR(100) NOT NULL,
    location     VARCHAR(100),
    country      VARCHAR(60),
    lat          DECIMAL(9,6),
    lng          DECIMAL(9,6),
    altitude_m   INT
);

INSERT INTO circuits
SELECT CAST(circuitId AS UNSIGNED),
       TRIM(circuitRef),
       TRIM(name),
       NULLIF(TRIM(location), '\\N'),                       -- C1, C3
       NULLIF(TRIM(country), '\\N'),
       CAST(NULLIF(lat, '\\N') AS DECIMAL(9,6)),            -- C2
       CAST(NULLIF(lng, '\\N') AS DECIMAL(9,6)),
       CAST(NULLIF(alt, '\\N') AS SIGNED)
FROM raw_circuits;

-- ---------------------------------------------------------------------
-- constructors
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS constructors;
CREATE TABLE constructors (
    constructor_id   INT          PRIMARY KEY,
    constructor_ref  VARCHAR(50)  NOT NULL,
    constructor_name VARCHAR(100) NOT NULL,
    nationality      VARCHAR(50)
);

INSERT INTO constructors
SELECT CAST(constructorId AS UNSIGNED),
       TRIM(constructorRef),
       TRIM(name),
       NULLIF(TRIM(nationality), '\\N')
FROM raw_constructors;

-- ---------------------------------------------------------------------
-- drivers
-- C3: 'Argentinian ' (trailing space, and a different spelling) is merged
--     into 'Argentine', which every other Argentine driver uses.
-- C8: drivers with no race, qualifying or sprint entry are dropped. These
--     are 2026 reserve/test drivers listed with no birth date or
--     nationality.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS drivers;
CREATE TABLE drivers (
    driver_id        INT          PRIMARY KEY,
    driver_ref       VARCHAR(50)  NOT NULL,
    permanent_number INT,
    code             CHAR(3),
    forename         VARCHAR(60)  NOT NULL,
    surname          VARCHAR(60)  NOT NULL,
    full_name        VARCHAR(125) NOT NULL,
    dob              DATE,
    nationality      VARCHAR(50)
);

INSERT INTO drivers
SELECT CAST(d.driverId AS UNSIGNED),
       TRIM(d.driverRef),
       CAST(NULLIF(d.number, '\\N') AS UNSIGNED),
       NULLIF(TRIM(d.code), '\\N'),
       TRIM(d.forename),
       TRIM(d.surname),
       CONCAT(TRIM(d.forename), ' ', TRIM(d.surname)),
       STR_TO_DATE(NULLIF(d.dob, '\\N'), '%Y-%m-%d'),
       CASE TRIM(d.nationality)
            WHEN '\\N'         THEN NULL
            WHEN 'Argentinian' THEN 'Argentine'
            ELSE TRIM(d.nationality)
       END
FROM raw_drivers d
WHERE EXISTS (SELECT 1 FROM raw_results r        WHERE r.driverId = d.driverId)
   OR EXISTS (SELECT 1 FROM raw_qualifying q     WHERE q.driverId = d.driverId)
   OR EXISTS (SELECT 1 FROM raw_sprint_results s WHERE s.driverId = d.driverId);

-- ---------------------------------------------------------------------
-- status  (C7: grouped into categories used throughout the EDA)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS status;
CREATE TABLE status (
    status_id       INT         PRIMARY KEY,
    status          VARCHAR(60) NOT NULL,
    status_category VARCHAR(30) NOT NULL
);

INSERT INTO status
SELECT CAST(statusId AS UNSIGNED),
       TRIM(status),
       CASE
         WHEN TRIM(status) = 'Finished'                                   THEN 'Finished'
         WHEN TRIM(status) LIKE '+%Lap%' OR TRIM(status) = 'Lapped'       THEN 'Lapped'
         WHEN TRIM(status) IN ('Accident','Collision','Collision damage','Spun off',
                               'Fatal accident','Damage','Debris','Broken wing',
                               'Front wing','Rear wing','Puncture','Tyre puncture')
                                                                          THEN 'Accident / damage'
         WHEN TRIM(status) IN ('Disqualified','Excluded','Underweight')   THEN 'Disqualified'
         WHEN TRIM(status) IN ('Did not qualify','Did not prequalify','107% Rule')
                                                                          THEN 'Did not qualify'
         WHEN TRIM(status) IN ('Did not start','Withdrew','Safety concerns')
                                                                          THEN 'Did not start'
         WHEN TRIM(status) IN ('Illness','Injured','Injury','Eye injury','Physical','Driver unwell')
                                                                          THEN 'Driver health'
         WHEN TRIM(status) = 'Not classified'                             THEN 'Not classified'
         WHEN TRIM(status) IN ('Retired','Not restarted','Safety')        THEN 'Other / unspecified'
         ELSE 'Mechanical'
       END
FROM raw_status;

-- ---------------------------------------------------------------------
-- races
-- Practice/qualifying session dates are out of scope and dropped.
-- C9: is_completed = 0 for scheduled rounds with no results yet.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS races;
CREATE TABLE races (
    race_id      INT          PRIMARY KEY,
    season       SMALLINT     NOT NULL,
    round        TINYINT      NOT NULL,
    circuit_id   INT          NOT NULL,
    race_name    VARCHAR(100) NOT NULL,
    race_date    DATE         NOT NULL,
    race_time    TIME,
    has_sprint   TINYINT(1)   NOT NULL,
    is_indy500   TINYINT(1)   NOT NULL,
    is_completed TINYINT(1)   NOT NULL,
    UNIQUE KEY uq_season_round (season, round)
);

INSERT INTO races
SELECT CAST(ra.raceId AS UNSIGNED),
       CAST(ra.year AS UNSIGNED),
       CAST(ra.round AS UNSIGNED),
       CAST(ra.circuitId AS UNSIGNED),
       TRIM(ra.name),
       STR_TO_DATE(ra.date, '%Y-%m-%d'),
       CAST(NULLIF(ra.time, '\\N') AS TIME),
       ra.sprint_date <> '\\N',
       TRIM(ra.name) = 'Indianapolis 500',
       EXISTS (SELECT 1 FROM raw_results r WHERE r.raceId = ra.raceId)
FROM raw_races ra;

-- ---------------------------------------------------------------------
-- results  (the main fact table)
-- C4: fastest lap 'm:ss.sss' -> ms. The race time column is NOT parsed
--     because it mixes total time and gaps ('+5.478'), and one value is
--     malformed ('2:4:44.859'). The clean 'milliseconds' column already
--     holds total race time, so that is used instead.
-- C5: grid 0 -> NULL. pit_lane_start = 1 when the car still started.
-- C6: outcome decoded from positionText (R, D, E, W, F, N, or a number).
--     finish_position comes from positionText, not position, because
--     from 2025 the source fills position for retired cars too.
-- C10: points_2010_scale scores every classified top-10 finish on the
--      25-18-15-12-10-8-6-4-2-1 scale, ignoring bonus points.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS results;
CREATE TABLE results (
    result_id          INT          PRIMARY KEY,
    race_id            INT          NOT NULL,
    driver_id          INT          NOT NULL,
    constructor_id     INT          NOT NULL,
    car_number         INT,
    grid               TINYINT,
    pit_lane_start     TINYINT(1)   NOT NULL,
    finish_position    TINYINT,
    position_text      VARCHAR(4)   NOT NULL,
    position_order     TINYINT      NOT NULL,
    outcome            VARCHAR(20)  NOT NULL,
    started            TINYINT(1)   NOT NULL,
    points             DECIMAL(5,2) NOT NULL,
    points_2010_scale  TINYINT      NOT NULL,
    laps               SMALLINT     NOT NULL,
    race_time_ms       INT,
    fastest_lap_number SMALLINT,
    fastest_lap_rank   TINYINT,
    fastest_lap_ms     INT,
    fastest_lap_kph    DECIMAL(7,3),
    status_id          INT          NOT NULL,
    KEY ix_race   (race_id),
    KEY ix_driver (driver_id),
    KEY ix_constructor (constructor_id)
);

INSERT INTO results
SELECT CAST(resultId AS UNSIGNED),
       CAST(raceId AS UNSIGNED),
       CAST(driverId AS UNSIGNED),
       CAST(constructorId AS UNSIGNED),
       CAST(NULLIF(number, '\\N') AS UNSIGNED),
       CAST(NULLIF(NULLIF(grid, '\\N'), '0') AS UNSIGNED),
       grid = '0' AND positionText NOT IN ('F', 'W'),
       -- positionText is the source of truth: 2 rows (2005 Australian GP)
       -- have a numeric positionText but a '\N' position.
       CASE WHEN positionText REGEXP '^[0-9]+$' THEN CAST(positionText AS UNSIGNED) END,
       positionText,
       CAST(positionOrder AS UNSIGNED),
       CASE positionText
            WHEN 'R' THEN 'Retired'
            WHEN 'D' THEN 'Disqualified'
            WHEN 'E' THEN 'Disqualified'
            WHEN 'W' THEN 'Did not start'
            WHEN 'F' THEN 'Did not qualify'
            WHEN 'N' THEN 'Not classified'
            ELSE 'Classified'
       END,
       positionText NOT IN ('F', 'W'),
       CAST(points AS DECIMAL(5,2)),
       CASE WHEN positionText REGEXP '^[0-9]+$' THEN
            CASE CAST(positionText AS UNSIGNED)
                 WHEN 1 THEN 25 WHEN 2 THEN 18 WHEN 3 THEN 15 WHEN 4 THEN 12
                 WHEN 5 THEN 10 WHEN 6 THEN 8  WHEN 7 THEN 6  WHEN 8 THEN 4
                 WHEN 9 THEN 2  WHEN 10 THEN 1 ELSE 0 END
            ELSE 0 END,
       CAST(laps AS UNSIGNED),
       CAST(NULLIF(milliseconds, '\\N') AS UNSIGNED),
       CAST(NULLIF(fastestLap, '\\N') AS UNSIGNED),
       CAST(NULLIF(`rank`, '\\N') AS UNSIGNED),
       CASE WHEN fastestLapTime REGEXP '^[0-9]+:[0-9]{2}\\.[0-9]{3}$'
            THEN CAST(SUBSTRING_INDEX(fastestLapTime, ':', 1) AS UNSIGNED) * 60000
               + ROUND(CAST(SUBSTRING_INDEX(fastestLapTime, ':', -1) AS DECIMAL(6,3)) * 1000)
       END,
       CAST(NULLIF(fastestLapSpeed, '\\N') AS DECIMAL(7,3)),
       CAST(statusId AS UNSIGNED)
FROM raw_results;

-- ---------------------------------------------------------------------
-- sprint_results  (same logic as results, sprint races since 2021)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS sprint_results;
CREATE TABLE sprint_results (
    sprint_result_id INT          PRIMARY KEY,
    race_id          INT          NOT NULL,
    driver_id        INT          NOT NULL,
    constructor_id   INT          NOT NULL,
    grid             TINYINT,
    finish_position  TINYINT,
    position_text    VARCHAR(4)   NOT NULL,
    points           DECIMAL(5,2) NOT NULL,
    laps             SMALLINT     NOT NULL,
    status_id        INT          NOT NULL,
    KEY ix_race (race_id), KEY ix_driver (driver_id)
);

INSERT INTO sprint_results
SELECT CAST(resultId AS UNSIGNED),
       CAST(raceId AS UNSIGNED),
       CAST(driverId AS UNSIGNED),
       CAST(constructorId AS UNSIGNED),
       CAST(NULLIF(NULLIF(grid, '\\N'), '0') AS UNSIGNED),
       -- Same rule as results. Two 2026 Miami sprint rows are marked 'W'
       -- (withdrew) yet carry position 20/21 and no status at all.
       CASE WHEN positionText REGEXP '^[0-9]+$' THEN CAST(positionText AS UNSIGNED) END,
       positionText,
       CAST(points AS DECIMAL(5,2)),
       CAST(laps AS UNSIGNED),
       CASE WHEN statusId = '\\N' AND positionText = 'W'
            THEN (SELECT CAST(statusId AS UNSIGNED) FROM raw_status WHERE status = 'Withdrew')
            ELSE CAST(statusId AS UNSIGNED) END
FROM raw_sprint_results;

-- ---------------------------------------------------------------------
-- qualifying  (C4: q1/q2/q3 'm:ss.sss' -> milliseconds)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS qualifying;
CREATE TABLE qualifying (
    qualify_id     INT     PRIMARY KEY,
    race_id        INT     NOT NULL,
    driver_id      INT     NOT NULL,
    constructor_id INT     NOT NULL,
    quali_position TINYINT NOT NULL,
    q1_ms          INT,
    q2_ms          INT,
    q3_ms          INT,
    best_lap_ms    INT,
    KEY ix_race (race_id), KEY ix_driver (driver_id)
);

INSERT INTO qualifying (qualify_id, race_id, driver_id, constructor_id,
                        quali_position, q1_ms, q2_ms, q3_ms)
SELECT CAST(qualifyId AS UNSIGNED),
       CAST(raceId AS UNSIGNED),
       CAST(driverId AS UNSIGNED),
       CAST(constructorId AS UNSIGNED),
       CAST(position AS UNSIGNED),
       CASE WHEN q1 REGEXP '^[0-9]+:[0-9]{2}\\.[0-9]{3}$'
            THEN CAST(SUBSTRING_INDEX(q1, ':', 1) AS UNSIGNED) * 60000
               + ROUND(CAST(SUBSTRING_INDEX(q1, ':', -1) AS DECIMAL(6,3)) * 1000) END,
       CASE WHEN q2 REGEXP '^[0-9]+:[0-9]{2}\\.[0-9]{3}$'
            THEN CAST(SUBSTRING_INDEX(q2, ':', 1) AS UNSIGNED) * 60000
               + ROUND(CAST(SUBSTRING_INDEX(q2, ':', -1) AS DECIMAL(6,3)) * 1000) END,
       CASE WHEN q3 REGEXP '^[0-9]+:[0-9]{2}\\.[0-9]{3}$'
            THEN CAST(SUBSTRING_INDEX(q3, ':', 1) AS UNSIGNED) * 60000
               + ROUND(CAST(SUBSTRING_INDEX(q3, ':', -1) AS DECIMAL(6,3)) * 1000) END
FROM raw_qualifying;

-- C12: one impossible lap. Mark Blundell, 1995 Japanese GP, q1 '16:42.640'
-- (pole was 1:38.023), almost certainly a typo for 1:42.640. It is set to
-- NULL rather than guessed. The derived table wrapper is needed because
-- MySQL cannot read from the table it is updating in a plain subquery.
UPDATE qualifying q
JOIN (SELECT race_id, MIN(q1_ms) AS fastest_q1
      FROM qualifying GROUP BY race_id) p ON p.race_id = q.race_id
SET q.q1_ms = NULL
WHERE q.q1_ms > 1.5 * p.fastest_q1;

-- Best lap across sessions. LEAST() returns NULL if any input is NULL,
-- so missing sessions are swapped for a large sentinel first.
UPDATE qualifying
SET best_lap_ms = NULLIF(LEAST(COALESCE(q1_ms, 99999999),
                               COALESCE(q2_ms, 99999999),
                               COALESCE(q3_ms, 99999999)), 99999999);

-- ---------------------------------------------------------------------
-- driver_standings / constructor_standings (championship table after
-- every round)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS driver_standings;
CREATE TABLE driver_standings (
    driver_standings_id INT          PRIMARY KEY,
    race_id             INT          NOT NULL,
    driver_id           INT          NOT NULL,
    points              DECIMAL(6,2) NOT NULL,
    standing_position   SMALLINT,
    wins                TINYINT      NOT NULL,
    UNIQUE KEY uq_race_driver (race_id, driver_id)
);

INSERT INTO driver_standings
SELECT CAST(driverStandingsId AS UNSIGNED), CAST(raceId AS UNSIGNED),
       CAST(driverId AS UNSIGNED), CAST(points AS DECIMAL(6,2)),
       CAST(NULLIF(position, '\\N') AS UNSIGNED), CAST(wins AS UNSIGNED)
FROM raw_driver_standings;

DROP TABLE IF EXISTS constructor_standings;
CREATE TABLE constructor_standings (
    constructor_standings_id INT          PRIMARY KEY,
    race_id                  INT          NOT NULL,
    constructor_id           INT          NOT NULL,
    points                   DECIMAL(6,2) NOT NULL,
    standing_position        SMALLINT,
    wins                     TINYINT      NOT NULL,
    UNIQUE KEY uq_race_constructor (race_id, constructor_id)
);

INSERT INTO constructor_standings
SELECT CAST(constructorStandingsId AS UNSIGNED), CAST(raceId AS UNSIGNED),
       CAST(constructorId AS UNSIGNED), CAST(points AS DECIMAL(6,2)),
       CAST(NULLIF(position, '\\N') AS UNSIGNED), CAST(wins AS UNSIGNED)
FROM raw_constructor_standings;

-- ---------------------------------------------------------------------
-- pit_stops  (duration text such as '22.345' or '16:44.123' after a red
-- flag is not parsed; the milliseconds column is used instead)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS pit_stops;
CREATE TABLE pit_stops (
    race_id     INT      NOT NULL,
    driver_id   INT      NOT NULL,
    stop_number TINYINT  NOT NULL,
    lap         SMALLINT NOT NULL,
    duration_ms INT,
    PRIMARY KEY (race_id, driver_id, stop_number)
);

INSERT INTO pit_stops
SELECT CAST(raceId AS UNSIGNED), CAST(driverId AS UNSIGNED),
       CAST(stop AS UNSIGNED), CAST(lap AS UNSIGNED),
       CAST(NULLIF(milliseconds, '\\N') AS UNSIGNED)
FROM raw_pit_stops;

-- ---------------------------------------------------------------------
-- C11: foreign keys
-- ---------------------------------------------------------------------
SET FOREIGN_KEY_CHECKS = 1;

ALTER TABLE races                 ADD CONSTRAINT fk_races_circuit   FOREIGN KEY (circuit_id)     REFERENCES circuits(circuit_id);
ALTER TABLE results               ADD CONSTRAINT fk_res_race        FOREIGN KEY (race_id)        REFERENCES races(race_id),
                                  ADD CONSTRAINT fk_res_driver      FOREIGN KEY (driver_id)      REFERENCES drivers(driver_id),
                                  ADD CONSTRAINT fk_res_constructor FOREIGN KEY (constructor_id) REFERENCES constructors(constructor_id),
                                  ADD CONSTRAINT fk_res_status      FOREIGN KEY (status_id)      REFERENCES status(status_id);
ALTER TABLE sprint_results        ADD CONSTRAINT fk_spr_race        FOREIGN KEY (race_id)        REFERENCES races(race_id),
                                  ADD CONSTRAINT fk_spr_driver      FOREIGN KEY (driver_id)      REFERENCES drivers(driver_id);
ALTER TABLE qualifying            ADD CONSTRAINT fk_q_race          FOREIGN KEY (race_id)        REFERENCES races(race_id),
                                  ADD CONSTRAINT fk_q_driver        FOREIGN KEY (driver_id)      REFERENCES drivers(driver_id);
ALTER TABLE driver_standings      ADD CONSTRAINT fk_ds_race         FOREIGN KEY (race_id)        REFERENCES races(race_id),
                                  ADD CONSTRAINT fk_ds_driver       FOREIGN KEY (driver_id)      REFERENCES drivers(driver_id);
ALTER TABLE constructor_standings ADD CONSTRAINT fk_cs_race         FOREIGN KEY (race_id)        REFERENCES races(race_id),
                                  ADD CONSTRAINT fk_cs_constructor  FOREIGN KEY (constructor_id) REFERENCES constructors(constructor_id);
ALTER TABLE pit_stops             ADD CONSTRAINT fk_ps_race         FOREIGN KEY (race_id)        REFERENCES races(race_id),
                                  ADD CONSTRAINT fk_ps_driver       FOREIGN KEY (driver_id)      REFERENCES drivers(driver_id);

-- ---------------------------------------------------------------------
-- Analysis view: one row per race entry with names and categories.
-- Every EDA script builds on this.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW v_results AS
SELECT r.*,
       ra.season,
       ra.round,
       ra.race_name,
       ra.race_date,
       ra.is_indy500,
       d.full_name        AS driver_name,
       d.nationality      AS driver_nationality,
       c.constructor_name,
       s.status,
       s.status_category,
       CASE WHEN ra.season < 1980 THEN '1950-1979'
            WHEN ra.season < 2000 THEN '1980-1999'
            WHEN ra.season < 2014 THEN '2000-2013'
            ELSE '2014-present (hybrid era)' END AS era,
       COALESCE(r.finish_position = 1, 0)  AS is_win,
       COALESCE(r.finish_position <= 3, 0) AS is_podium,
       COALESCE(r.grid = 1, 0)             AS is_pole
FROM results r
JOIN races        ra ON ra.race_id        = r.race_id
JOIN drivers      d  ON d.driver_id       = r.driver_id
JOIN constructors c  ON c.constructor_id  = r.constructor_id
JOIN status       s  ON s.status_id       = r.status_id;
