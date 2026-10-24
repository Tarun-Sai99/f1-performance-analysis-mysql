-- =====================================================================
-- 00_setup.sql
-- Creates the f1 database and one raw staging table per CSV file.
-- Every raw column is VARCHAR on purpose: the raw layer stores the files
-- exactly as delivered (including the literal \N null markers), so that
-- all type fixes happen visibly in 03_cleaning.sql.
-- =====================================================================

DROP DATABASE IF EXISTS f1;
CREATE DATABASE f1 CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE f1;

DROP TABLE IF EXISTS raw_circuits;
CREATE TABLE raw_circuits (
    circuitId                VARCHAR(255),
    circuitRef               VARCHAR(255),
    name                     VARCHAR(255),
    location                 VARCHAR(255),
    country                  VARCHAR(255),
    lat                      VARCHAR(255),
    lng                      VARCHAR(255),
    alt                      VARCHAR(255),
    url                      VARCHAR(500)
);

DROP TABLE IF EXISTS raw_constructor_standings;
CREATE TABLE raw_constructor_standings (
    constructorStandingsId   VARCHAR(255),
    raceId                   VARCHAR(255),
    constructorId            VARCHAR(255),
    points                   VARCHAR(255),
    position                 VARCHAR(255),
    positionText             VARCHAR(255),
    wins                     VARCHAR(255)
);

DROP TABLE IF EXISTS raw_constructors;
CREATE TABLE raw_constructors (
    constructorId            VARCHAR(255),
    constructorRef           VARCHAR(255),
    name                     VARCHAR(255),
    nationality              VARCHAR(255),
    url                      VARCHAR(500)
);

DROP TABLE IF EXISTS raw_driver_standings;
CREATE TABLE raw_driver_standings (
    driverStandingsId        VARCHAR(255),
    raceId                   VARCHAR(255),
    driverId                 VARCHAR(255),
    points                   VARCHAR(255),
    position                 VARCHAR(255),
    positionText             VARCHAR(255),
    wins                     VARCHAR(255)
);

DROP TABLE IF EXISTS raw_drivers;
CREATE TABLE raw_drivers (
    driverId                 VARCHAR(255),
    driverRef                VARCHAR(255),
    number                   VARCHAR(255),
    code                     VARCHAR(255),
    forename                 VARCHAR(255),
    surname                  VARCHAR(255),
    dob                      VARCHAR(255),
    nationality              VARCHAR(255),
    url                      VARCHAR(500)
);

DROP TABLE IF EXISTS raw_pit_stops;
CREATE TABLE raw_pit_stops (
    raceId                   VARCHAR(255),
    driverId                 VARCHAR(255),
    stop                     VARCHAR(255),
    lap                      VARCHAR(255),
    time                     VARCHAR(255),
    duration                 VARCHAR(255),
    milliseconds             VARCHAR(255)
);

DROP TABLE IF EXISTS raw_qualifying;
CREATE TABLE raw_qualifying (
    qualifyId                VARCHAR(255),
    raceId                   VARCHAR(255),
    driverId                 VARCHAR(255),
    constructorId            VARCHAR(255),
    number                   VARCHAR(255),
    position                 VARCHAR(255),
    q1                       VARCHAR(255),
    q2                       VARCHAR(255),
    q3                       VARCHAR(255)
);

DROP TABLE IF EXISTS raw_races;
CREATE TABLE raw_races (
    raceId                   VARCHAR(255),
    year                     VARCHAR(255),
    round                    VARCHAR(255),
    circuitId                VARCHAR(255),
    name                     VARCHAR(255),
    date                     VARCHAR(255),
    time                     VARCHAR(255),
    url                      VARCHAR(500),
    fp1_date                 VARCHAR(255),
    fp1_time                 VARCHAR(255),
    fp2_date                 VARCHAR(255),
    fp2_time                 VARCHAR(255),
    fp3_date                 VARCHAR(255),
    fp3_time                 VARCHAR(255),
    quali_date               VARCHAR(255),
    quali_time               VARCHAR(255),
    sprint_date              VARCHAR(255),
    sprint_time              VARCHAR(255)
);

DROP TABLE IF EXISTS raw_results;
CREATE TABLE raw_results (
    resultId                 VARCHAR(255),
    raceId                   VARCHAR(255),
    driverId                 VARCHAR(255),
    constructorId            VARCHAR(255),
    number                   VARCHAR(255),
    grid                     VARCHAR(255),
    position                 VARCHAR(255),
    positionText             VARCHAR(255),
    positionOrder            VARCHAR(255),
    points                   VARCHAR(255),
    laps                     VARCHAR(255),
    time                     VARCHAR(255),
    milliseconds             VARCHAR(255),
    fastestLap               VARCHAR(255),
    rank                     VARCHAR(255),
    fastestLapTime           VARCHAR(255),
    fastestLapSpeed          VARCHAR(255),
    statusId                 VARCHAR(255)
);

DROP TABLE IF EXISTS raw_sprint_results;
CREATE TABLE raw_sprint_results (
    resultId                 VARCHAR(255),
    raceId                   VARCHAR(255),
    driverId                 VARCHAR(255),
    constructorId            VARCHAR(255),
    number                   VARCHAR(255),
    grid                     VARCHAR(255),
    position                 VARCHAR(255),
    positionText             VARCHAR(255),
    positionOrder            VARCHAR(255),
    points                   VARCHAR(255),
    laps                     VARCHAR(255),
    time                     VARCHAR(255),
    milliseconds             VARCHAR(255),
    fastestLap               VARCHAR(255),
    fastestLapTime           VARCHAR(255),
    statusId                 VARCHAR(255),
    rank                     VARCHAR(255)
);

DROP TABLE IF EXISTS raw_status;
CREATE TABLE raw_status (
    statusId                 VARCHAR(255),
    status                   VARCHAR(255)
);

