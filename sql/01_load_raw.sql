-- =====================================================================
-- 01_load_raw.sql
-- Loads the CSVs into the raw_* tables.
-- Run from the repository root with local infile enabled:
--   mysql --local-infile=1 -u root -p < sql/01_load_raw.sql
-- ESCAPED BY '' keeps \N as the literal text '\N' instead of letting
-- MySQL silently convert it, so the cleaning step can count and fix it.
-- =====================================================================

USE f1;

TRUNCATE TABLE raw_circuits;
LOAD DATA LOCAL INFILE 'data/raw/circuits.csv'
INTO TABLE raw_circuits
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(circuitId, circuitRef, name, location, country, lat, lng, alt, url);

TRUNCATE TABLE raw_constructor_standings;
LOAD DATA LOCAL INFILE 'data/raw/constructor_standings.csv'
INTO TABLE raw_constructor_standings
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(constructorStandingsId, raceId, constructorId, points, position, positionText, wins);

TRUNCATE TABLE raw_constructors;
LOAD DATA LOCAL INFILE 'data/raw/constructors.csv'
INTO TABLE raw_constructors
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(constructorId, constructorRef, name, nationality, url);

TRUNCATE TABLE raw_driver_standings;
LOAD DATA LOCAL INFILE 'data/raw/driver_standings.csv'
INTO TABLE raw_driver_standings
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(driverStandingsId, raceId, driverId, points, position, positionText, wins);

TRUNCATE TABLE raw_drivers;
LOAD DATA LOCAL INFILE 'data/raw/drivers.csv'
INTO TABLE raw_drivers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(driverId, driverRef, number, code, forename, surname, dob, nationality, url);

TRUNCATE TABLE raw_pit_stops;
LOAD DATA LOCAL INFILE 'data/raw/pit_stops.csv'
INTO TABLE raw_pit_stops
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(raceId, driverId, stop, lap, time, duration, milliseconds);

TRUNCATE TABLE raw_qualifying;
LOAD DATA LOCAL INFILE 'data/raw/qualifying.csv'
INTO TABLE raw_qualifying
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(qualifyId, raceId, driverId, constructorId, number, position, q1, q2, q3);

TRUNCATE TABLE raw_races;
LOAD DATA LOCAL INFILE 'data/raw/races.csv'
INTO TABLE raw_races
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(raceId, year, round, circuitId, name, date, time, url, fp1_date, fp1_time, fp2_date, fp2_time, fp3_date, fp3_time, quali_date, quali_time, sprint_date, sprint_time);

TRUNCATE TABLE raw_results;
LOAD DATA LOCAL INFILE 'data/raw/results.csv'
INTO TABLE raw_results
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(resultId, raceId, driverId, constructorId, number, grid, position, positionText, positionOrder, points, laps, time, milliseconds, fastestLap, rank, fastestLapTime, fastestLapSpeed, statusId);

TRUNCATE TABLE raw_sprint_results;
LOAD DATA LOCAL INFILE 'data/raw/sprint_results.csv'
INTO TABLE raw_sprint_results
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(resultId, raceId, driverId, constructorId, number, grid, position, positionText, positionOrder, points, laps, time, milliseconds, fastestLap, fastestLapTime, statusId, rank);

TRUNCATE TABLE raw_status;
LOAD DATA LOCAL INFILE 'data/raw/status.csv'
INTO TABLE raw_status
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' ESCAPED BY ''
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(statusId, status);

-- Row counts after load (compare with `wc -l data/raw/*.csv` minus headers)
SELECT 'raw_circuits' AS table_name, COUNT(*) AS row_count FROM raw_circuits UNION ALL
SELECT 'raw_constructor_standings' AS table_name, COUNT(*) AS row_count FROM raw_constructor_standings UNION ALL
SELECT 'raw_constructors' AS table_name, COUNT(*) AS row_count FROM raw_constructors UNION ALL
SELECT 'raw_driver_standings' AS table_name, COUNT(*) AS row_count FROM raw_driver_standings UNION ALL
SELECT 'raw_drivers' AS table_name, COUNT(*) AS row_count FROM raw_drivers UNION ALL
SELECT 'raw_pit_stops' AS table_name, COUNT(*) AS row_count FROM raw_pit_stops UNION ALL
SELECT 'raw_qualifying' AS table_name, COUNT(*) AS row_count FROM raw_qualifying UNION ALL
SELECT 'raw_races' AS table_name, COUNT(*) AS row_count FROM raw_races UNION ALL
SELECT 'raw_results' AS table_name, COUNT(*) AS row_count FROM raw_results UNION ALL
SELECT 'raw_sprint_results' AS table_name, COUNT(*) AS row_count FROM raw_sprint_results UNION ALL
SELECT 'raw_status' AS table_name, COUNT(*) AS row_count FROM raw_status;
