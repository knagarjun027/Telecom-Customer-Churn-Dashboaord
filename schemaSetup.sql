-- 0) make DB and use it
CREATE DATABASE IF NOT EXISTS telco_di;
USE telco_di;

-- 1) raw source table copy (optional, if dump created in other DB)
-- If your dump already created mytable in telco_di, skip this. Otherwise:
-- CREATE TABLE mytable (...) -- comes from your SQL dump

-- 2) Dimensions
DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer (
  customer_id VARCHAR(20) PRIMARY KEY,
  gender VARCHAR(10),
  senior_citizen TINYINT,
  partner VARCHAR(5),
  dependents VARCHAR(5)
);

DROP TABLE IF EXISTS dim_contract;
CREATE TABLE dim_contract (
  contract_id INT AUTO_INCREMENT PRIMARY KEY,
  contract_type VARCHAR(32),
  paperless_billing VARCHAR(5),
  payment_method VARCHAR(50),
  UNIQUE KEY uq_contract(contract_type, paperless_billing, payment_method)
);

DROP TABLE IF EXISTS dim_service;
CREATE TABLE dim_service (
  service_id INT AUTO_INCREMENT PRIMARY KEY,
  phone_service VARCHAR(20),
  multiple_lines VARCHAR(30),
  internet_service VARCHAR(30),
  online_security VARCHAR(30),
  online_backup VARCHAR(30),
  device_protection VARCHAR(30),
  tech_support VARCHAR(30),
  streaming_tv VARCHAR(30),
  streaming_movies VARCHAR(30),
  UNIQUE KEY uq_service(phone_service,multiple_lines,internet_service)
);

DROP TABLE IF EXISTS dim_tenure;
CREATE TABLE dim_tenure (
  tenure_id INT AUTO_INCREMENT PRIMARY KEY,
  tenure_min INT,
  tenure_max INT,
  label VARCHAR(30)
);

-- 3) Fact table (one row per customer snapshot)
DROP TABLE IF EXISTS fact_customer_subscription;
CREATE TABLE fact_customer_subscription (
  customer_id VARCHAR(20) PRIMARY KEY,
  contract_id INT,
  service_id INT,
  tenure INT,                 -- months
  monthly_charges DECIMAL(8,2),
  total_charges DECIMAL(10,2),
  churn_flag VARCHAR(3),     -- 'Yes'/'No' in your dump
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (contract_id) REFERENCES dim_contract(contract_id),
  FOREIGN KEY (service_id) REFERENCES dim_service(service_id)
);

-- 4) Populate dims from mytable (source)
-- dim_customer
INSERT INTO dim_customer (customer_id, gender, senior_citizen, partner, dependents)
SELECT DISTINCT customerID, gender, SeniorCitizen, Partner, Dependents
FROM mytable
WHERE customerID IS NOT NULL;

-- dim_contract: insert unique contract combos and get ids
INSERT IGNORE INTO dim_contract (contract_type, paperless_billing, payment_method)
SELECT DISTINCT Contract, PaperlessBilling, PaymentMethod
FROM mytable;

-- dim_service
INSERT IGNORE INTO dim_service (phone_service, multiple_lines, internet_service,
    online_security, online_backup, device_protection, tech_support, streaming_tv, streaming_movies)
SELECT DISTINCT PhoneService, MultipleLines, InternetService,
       OnlineSecurity, OnlineBackup, DeviceProtection, TechSupport, StreamingTV, StreamingMovies
FROM mytable;

-- dim_tenure (buckets) — choose buckets that make sense
INSERT INTO dim_tenure (tenure_min, tenure_max, label) VALUES
(0,3,'0-3 months'),
(4,12,'4-12 months'),
(13,24,'13-24 months'),
(25,48,'25-48 months'),
(49,9999,'49+ months');

-- 5) Populate fact table by joining to dims to get FK ids
INSERT INTO fact_customer_subscription (customer_id, contract_id, service_id, tenure, monthly_charges, total_charges, churn_flag)
SELECT
  s.customerID,
  c.contract_id,
  sv.service_id,
  s.tenure,
  s.MonthlyCharges,
  s.TotalCharges,
  s.Churn
FROM mytable s
LEFT JOIN dim_contract c
  ON c.contract_type = s.Contract
  AND c.paperless_billing = s.PaperlessBilling
  AND c.payment_method = s.PaymentMethod
LEFT JOIN dim_service sv
  ON sv.phone_service = s.PhoneService
  AND sv.multiple_lines = s.MultipleLines
  AND sv.internet_service = s.InternetService;

-- 6) Indexes for performance
CREATE INDEX idx_fact_churn ON fact_customer_subscription(churn_flag);
CREATE INDEX idx_fact_tenure ON fact_customer_subscription(tenure);
CREATE INDEX idx_dim_contract_type ON dim_contract(contract_type);

-- 7) Quick sanity checks
SELECT COUNT(*) AS rows_raw FROM mytable;
SELECT COUNT(*) AS customers_fact FROM fact_customer_subscription;
SELECT COUNT(*) AS distinct_contracts FROM dim_contract;
SELECT COUNT(*) AS distinct_services FROM dim_service;

-- removing white spaces to calculate service combos
-- creating a table to remove these white spaces if they exist

-- remove old tmp if present
DROP TABLE IF EXISTS tmp_service_combos;

CREATE TABLE tmp_service_combos AS
SELECT DISTINCT
  TRIM(PhoneService)          AS phone_service,
  TRIM(MultipleLines)         AS multiple_lines,
  TRIM(InternetService)       AS internet_service,
  TRIM(OnlineSecurity)        AS online_security,
  TRIM(OnlineBackup)          AS online_backup,
  TRIM(DeviceProtection)      AS device_protection,
  TRIM(TechSupport)           AS tech_support,
  TRIM(StreamingTV)           AS streaming_tv,
  TRIM(StreamingMovies)       AS streaming_movies
FROM mytable;

SELECT COUNT(*) AS tmp_bundle_count FROM tmp_service_combos; -- should return 322
SELECT * FROM tmp_service_combos;

-- re-inserting the remaining combos into the schema

INSERT INTO dim_service (
    phone_service, multiple_lines, internet_service,
    online_security, online_backup, device_protection,
    tech_support, streaming_tv, streaming_movies
)
SELECT t.phone_service, t.multiple_lines, t.internet_service,
       t.online_security, t.online_backup, t.device_protection,
       t.tech_support, t.streaming_tv, t.streaming_movies
FROM tmp_service_combos t
LEFT JOIN dim_service d
  ON UPPER(TRIM(d.phone_service)) = UPPER(TRIM(t.phone_service))
  AND UPPER(TRIM(d.multiple_lines)) = UPPER(TRIM(t.multiple_lines))
  AND UPPER(TRIM(d.internet_service)) = UPPER(TRIM(t.internet_service))
  AND UPPER(TRIM(d.online_security)) = UPPER(TRIM(t.online_security))
  AND UPPER(TRIM(d.online_backup)) = UPPER(TRIM(t.online_backup))
  AND UPPER(TRIM(d.device_protection)) = UPPER(TRIM(t.device_protection))
  AND UPPER(TRIM(d.tech_support)) = UPPER(TRIM(t.tech_support))
  AND UPPER(TRIM(d.streaming_tv)) = UPPER(TRIM(t.streaming_tv))
  AND UPPER(TRIM(d.streaming_movies)) = UPPER(TRIM(t.streaming_movies))
WHERE d.service_id IS NULL;

SELECT COUNT(*) AS dim_rows_after FROM dim_service;
-- Expect dim_rows_after >= previous count and equal to tmp_bundle_count (322) if dim was empty.

-- Add the FK column if not exists
ALTER TABLE fact_customer_subscription
  ADD COLUMN IF NOT EXISTS service_id INT;

-- Update fact rows setting service_id by joining on all 9 bundle fields from source mytable
UPDATE fact_customer_subscription f
JOIN mytable m ON f.customer_id = m.customerID
JOIN dim_service s
  ON UPPER(TRIM(s.phone_service)) = UPPER(TRIM(m.PhoneService))
  AND UPPER(TRIM(s.multiple_lines)) = UPPER(TRIM(m.MultipleLines))
  AND UPPER(TRIM(s.internet_service)) = UPPER(TRIM(m.InternetService))
  AND UPPER(TRIM(s.online_security)) = UPPER(TRIM(m.OnlineSecurity))
  AND UPPER(TRIM(s.online_backup)) = UPPER(TRIM(m.OnlineBackup))
  AND UPPER(TRIM(s.device_protection)) = UPPER(TRIM(m.DeviceProtection))
  AND UPPER(TRIM(s.tech_support)) = UPPER(TRIM(m.TechSupport))
  AND UPPER(TRIM(s.streaming_tv)) = UPPER(TRIM(m.StreamingTV))
  AND UPPER(TRIM(s.streaming_movies)) = UPPER(TRIM(m.StreamingMovies))
SET f.service_id = s.service_id;

SELECT COUNT(*) AS missing_service_fk
FROM fact_customer_subscription
WHERE service_id IS NULL;

ALTER TABLE fact_customer_subscription
  ADD CONSTRAINT fk_service
  FOREIGN KEY (service_id) REFERENCES dim_service(service_id);
-- end

-- conencting tenure to fact table

ALTER TABLE fact_customer_subscription
  ADD COLUMN tenure_id INT;

UPDATE fact_customer_subscription f
JOIN dim_tenure t 
  ON f.tenure BETWEEN t.tenure_min AND t.tenure_max
SET f.tenure_id = t.tenure_id;

ALTER TABLE fact_customer_subscription
  ADD CONSTRAINT fk_tenure
  FOREIGN KEY (tenure_id) REFERENCES dim_tenure(tenure_id);


