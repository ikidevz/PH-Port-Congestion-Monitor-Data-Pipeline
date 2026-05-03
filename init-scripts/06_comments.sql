\c ph_port_monitor

COMMENT ON COLUMN marts.congestion_scores.congestion_score IS
    'Weighted composite: (active/capacity)*0.40 + (avg_wait/24)*0.35 + (arrivals/avg_rate)*0.25, scaled to 100';