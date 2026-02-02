-- 1) Overall Churn Rate
SELECT
  COUNT(*) AS total_customers,
  SUM(CASE WHEN churn_flag = 'Yes' THEN 1 ELSE 0 END) AS churned,
  ROUND(100 * SUM(CASE WHEN churn_flag = 'Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM fact_customer_subscription;

-- 2) Churn Rate by Gender
SELECT
  c.gender,
  COUNT(*) AS customers,
  SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) AS churned,
  ROUND(100*SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END)/COUNT(*),2) AS churn_rate_pct
FROM fact_customer_subscription f
JOIN dim_customer c ON f.customer_id = c.customer_id
GROUP BY c.gender
ORDER BY churn_rate_pct DESC;

-- 3) Churn Rate by Contract Type
SELECT
  d.contract_type,
  COUNT(*) AS customers,
  SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) AS churned,
  ROUND(100 * SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM fact_customer_subscription f
LEFT JOIN dim_contract d ON f.contract_id = d.contract_id
GROUP BY d.contract_type
ORDER BY churn_rate_pct DESC;

-- 4) Churn Rate by Tenure Group (uses dim_tenure)
SELECT
  t.label AS tenure_group,
  COUNT(*) AS customers,
  SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) AS churned,
  ROUND(100 * SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM fact_customer_subscription f
JOIN dim_tenure t ON f.tenure BETWEEN t.tenure_min AND t.tenure_max
GROUP BY t.tenure_id, t.label
ORDER BY t.tenure_min;

-- 5) Internet Service Impact
SELECT
  s.internet_service,
  COUNT(*) AS customers,
  SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) AS churned,
  ROUND(100 * SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM fact_customer_subscription f
JOIN dim_service s ON f.service_id = s.service_id
GROUP BY s.internet_service
ORDER BY churn_rate_pct DESC;

-- 6) Payment Method Impact
SELECT
  d.payment_method,
  COUNT(*) AS customers,
  SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) AS churned,
  ROUND(100 * SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM fact_customer_subscription f
LEFT JOIN dim_contract d ON f.contract_id = d.contract_id
GROUP BY d.payment_method
ORDER BY churn_rate_pct DESC;

-- 7) Streaming (TV/Movies) vs Churn — bundle level
SELECT
  s.streaming_tv, s.streaming_movies,
  COUNT(*) AS customers,
  SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) AS churned,
  ROUND(100 * SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END)/COUNT(*),2) AS churn_rate_pct
FROM fact_customer_subscription f
JOIN dim_service s ON f.service_id = s.service_id
GROUP BY s.streaming_tv, s.streaming_movies
ORDER BY churn_rate_pct DESC;

-- 8) Senior Citizens Churn Propensity
SELECT
  CASE WHEN c.senior_citizen = 1 THEN 'Senior' ELSE 'Non-Senior' END AS age_group,
  COUNT(*) AS customers,
  SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) AS churned,
  ROUND(100 * SUM(CASE WHEN f.churn_flag='Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS churn_rate_pct
FROM fact_customer_subscription f
JOIN dim_customer c ON f.customer_id = c.customer_id
GROUP BY age_group;
