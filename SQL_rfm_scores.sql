WITH rfm_numbers AS (
  SELECT 
    CustomerID, 
    COUNT(DISTINCT InvoiceNo) AS Frequency, 
    DATE_DIFF( "2011-12-01", MAX(DATE(InvoiceDate)), DAY) AS Recency,
    ROUND(SUM(UnitPrice * Quantity), 2) Money_value
  FROM `tc-da-1.turing_data_analytics.rfm` 
  WHERE DATE(InvoiceDate) BETWEEN "2010-12-01" AND "2011-11-30"
  AND CustomerID IS NOT NULL
  AND Quantity > 0
  AND UnitPrice > 0
  GROUP BY CustomerID
  ),

quantiles AS (
  SELECT 
  APPROX_QUANTILES(Recency,4) AS RQ,
  APPROX_QUANTILES(Frequency,4) AS FQ,
  APPROX_QUANTILES(Money_value,4) AS MQ
  FROM rfm_numbers
),

rfm_scores AS (
  SELECT
    CustomerID,
    Frequency,
    Recency,
    Money_value,
    CASE 
      WHEN (SELECT RQ [OFFSET(1)] FROM quantiles) >= Recency THEN 1 -- last purchase <= 16 days
      WHEN (SELECT RQ [OFFSET(2)] FROM quantiles) >= Recency THEN 2 -- last purchase <= 49 days
      WHEN (SELECT RQ [OFFSET(3)] FROM quantiles) >= Recency THEN 3 -- last purchase <= 142 days
      ELSE 4 -- last purchase more than 142 days
      END AS R_score,
    CASE 
      WHEN (SELECT FQ [OFFSET(1)] FROM quantiles) >= Frequency THEN 4 -- 1 order
      WHEN (SELECT FQ [OFFSET(2)] FROM quantiles) >= Frequency THEN 3 -- 2 orders
      WHEN (SELECT FQ [OFFSET(3)] FROM quantiles) >= Frequency THEN 2 -- 3-4 orders
      ELSE 1 -- more than 4 orders
      END AS F_score,
    CASE 
      WHEN (SELECT MQ [OFFSET(1)] FROM quantiles) >= Money_value THEN 4 -- spent <= 305.1
      WHEN (SELECT MQ [OFFSET(2)] FROM quantiles) >= Money_value THEN 3 -- spent <= 656.25
      WHEN (SELECT MQ [OFFSET(3)] FROM quantiles) >= Money_value THEN 2 -- spent <= 1591.45
      ELSE 1 -- spent more than 1591.45
      END AS M_score
    -- because of a lot of 1 time orders, NTILE would assign 3 and 4 to Frequency of 1. Due to more issues like that I used quantile values as indicators for RFM scores
  FROM rfm_numbers
)

SELECT
  CustomerID,
  Recency,
  Frequency,
  Money_value,
  R_score,
  F_score,
  M_score,
  CONCAT(R_score, F_score, M_score) AS RFM_score,
  CASE
    WHEN CONCAT(R_score, F_score, M_score) = "111" THEN "Best customers" -- buy and spend the most, purchgased recently
    WHEN CONCAT(R_score, F_score, M_score) = "444" THEN "Lost" -- haven't purchased for a long time and never spent much
    WHEN R_score = 4 AND  F_score <= 2 AND M_score = 1 THEN "Can't Lose Them" --  high spenders who purchased often and have stopped buying for a long time
    WHEN R_score <= 2 AND F_score <= 2 AND M_score <= 2 THEN "Loyal Customers" -- purchase frequently and recently with moderate or high spending
    WHEN R_score <= 2 AND F_score <= 3 AND M_score <= 3 THEN "Potential Loyalists" -- made a few recent purchases of moderate value
    WHEN R_score >= 3 AND F_score <= 3 AND M_score = 1 THEN "At Risk" -- used to spend and more than once a lot but some time ago
    WHEN R_score >= 3 AND M_score <= 2 THEN "Need Attention" -- purchased spent above average but long time ago
    WHEN R_score >= 3 AND M_score >= 3 THEN "About To Sleep" -- close to hibernating clients, low spenders
    WHEN R_score <= 2 THEN "New Customers" -- purchased recently but have not spent much
    ELSE "" END AS Segments
FROM rfm_scores
