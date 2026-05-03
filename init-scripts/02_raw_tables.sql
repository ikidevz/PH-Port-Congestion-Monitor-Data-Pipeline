\c ph_port_monitor

-- ---------------------------------------------------------------------------
-- raw.vessel_events
-- Source-of-truth. Never mutate rows here. Append-only.
-- ---------------------------------------------------------------------------

CREATE TABLE raw.vessel_events (
    event_id              UUID         PRIMARY KEY,
    vessel_name           VARCHAR(120) NOT NULL,
    imo_number            VARCHAR(20)  NOT NULL,
    port_code             VARCHAR(5)   NOT NULL,          -- MNL, CEB, DVO …
    berth_id              SMALLINT     NOT NULL,
    event_type            VARCHAR(15)  NOT NULL           -- ARRIVAL | DEPARTURE
                            CHECK (event_type IN ('ARRIVAL', 'DEPARTURE')),
    cargo_type            VARCHAR(20)  NOT NULL           -- CONTAINER | RORO | BULK …
                            CHECK (cargo_type IN ('CONTAINER','RORO','BULK','TANKER','PASSENGER','GENERAL')),
    shipping_line         VARCHAR(80),
    gross_tonnage         INTEGER      NOT NULL CHECK (gross_tonnage > 0),
    draft_meters          NUMERIC(4,1) NOT NULL CHECK (draft_meters > 0),
    expected_duration_hrs NUMERIC(5,1) NOT NULL CHECK (expected_duration_hrs > 0),
    event_timestamp       TIMESTAMPTZ  NOT NULL,
    source                VARCHAR(20)  NOT NULL DEFAULT 'synthetic',
    ingested_at           TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);


-- ---------------------------------------------------------------------------
-- raw.ports
-- Reference dimension. Seed once; rarely changes.
-- ---------------------------------------------------------------------------

CREATE TABLE raw.ports (
    port_code    VARCHAR(5)   PRIMARY KEY,
    port_name    VARCHAR(120) NOT NULL,
    region       VARCHAR(80),
    berth_count  SMALLINT     NOT NULL CHECK (berth_count > 0),
    operator     VARCHAR(120),                            -- ICTSI, ATI, SPIA …
    latitude     NUMERIC(8,5),
    longitude    NUMERIC(8,5),
    is_active    BOOLEAN      NOT NULL DEFAULT TRUE,
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

INSERT INTO raw.ports (port_code, port_name, region, berth_count, operator, latitude, longitude) VALUES
    ('MNL', 'Port of Manila (MICT / South Harbor / North Harbor)', 'NCR', 22, 'ICTSI / ATI', 14.58333, 120.96667),
    ('CEB', 'Cebu International Port', 'Central Visayas', 5, 'CPA', 10.30639, 123.92611),
    ('DVO', 'Sasa Port Davao', 'Davao Region', 7, 'PPA', 7.12823, 125.66371),
    ('ILO', 'Iloilo Commercial Port Complex', 'Western Visayas', 5, 'ICTSI', 10.71111, 122.59333),
    ('GEN', 'General Santos Fishport Complex (Makar Wharf)', 'SOCCSKSARGEN', 6, 'PPA', 6.11389, 125.17278),
    ('ZAM', 'Zamboanga Port', 'Zamboanga Peninsula', 4, 'PPA', 6.90730, 122.05920),
    ('BTG', 'Batangas International Port', 'CALABARZON', 8, 'ATI / PPA', 13.75432, 121.04339),
    ('CGY', 'Port of Cagayan de Oro (Macabalan)', 'Northern Mindanao', 7, 'PPA', 8.49391, 124.66229),
    ('SUB', 'Subic Bay Port and Freeport Zone', 'Central Luzon', 25, 'SBMA', 14.80769, 120.28425),
    ('TAC', 'Port of Tacloban', 'Eastern Visayas', 4, 'PPA', 11.25250, 124.99810),
    ('OZA', 'Port of Ozamiz', 'Northern Mindanao', 3, 'PPA', 8.13957, 123.84355),
    ('ILG', 'Port of Iligan', 'Northern Mindanao', 5, 'PPA', 8.22806, 124.21528),
    ('PAG', 'Port of Pagadian', 'Zamboanga Peninsula', 3, 'PPA', 7.81667, 123.43333),
    ('CBO', 'Port of Cotabato', 'BARMM', 4, 'PPA', 7.21667, 124.25000),
    ('DIP', 'Port of Dipolog', 'Northern Mindanao', 3, 'PPA', 8.56667, 123.33333),
    ('TAG', 'Port of Tagbilaran', 'Central Visayas', 4, 'PPA', 9.65000, 123.85000),
    ('TAC2', 'Port of Catbalogan', 'Eastern Visayas', 3, 'PPA', 11.78333, 124.88333),
    ('SUG', 'Port of Surigao', 'Caraga', 4, 'PPA', 9.78333, 125.50000),
    ('BUT', 'Port of Butuan (Masao)', 'Caraga', 3, 'PPA', 8.95000, 125.61667),
    ('LBP', 'Port of Legazpi', 'Bicol Region', 4, 'PPA', 13.15000, 123.76667),
    ('ROM', 'Port of Romblon', 'MIMAROPA', 2, 'PPA', 12.58333, 122.26667),
    ('MAS', 'Port of Masbate', 'Bicol Region', 3, 'PPA', 12.36667, 123.61667);