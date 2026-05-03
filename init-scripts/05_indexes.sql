\c ph_port_monitor

CREATE INDEX idx_raw_ve_port      ON raw.vessel_events (port_code);
CREATE INDEX idx_raw_ve_ts        ON raw.vessel_events (event_timestamp DESC);
CREATE INDEX idx_raw_ve_imo       ON raw.vessel_events (imo_number);
CREATE INDEX idx_raw_ve_type      ON raw.vessel_events (event_type);

CREATE INDEX idx_cs_port_hour     ON marts.congestion_scores (port_code, score_hour DESC);
CREATE INDEX idx_cs_level         ON marts.congestion_scores (congestion_level);
CREATE INDEX idx_cs_score         ON marts.congestion_scores (congestion_score DESC);

CREATE INDEX idx_vt_port         ON marts.vessel_turnaround (port_code);
CREATE INDEX idx_vt_arrived      ON marts.vessel_turnaround (arrived_at DESC);
CREATE INDEX idx_vt_imo          ON marts.vessel_turnaround (imo_number);
CREATE INDEX idx_vt_delayed      ON marts.vessel_turnaround (is_delayed) WHERE is_delayed = TRUE;

CREATE INDEX idx_al_port         ON marts.alert_log (port_code, triggered_at DESC);
CREATE INDEX idx_al_notified     ON marts.alert_log (notified) WHERE notified = FALSE;