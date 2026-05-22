SELECT
      DATE_TRUNC('month', event_time) AS month,
      event_type,
      COUNT(DISTINCT vehicle_id) AS event_count
  FROM auto.tbl_auto_quotation_event
  WHERE event_type IN (
          'CAPVehicleDetailsRecorded',
          'FutureValuationFetched'
      )
      AND event_time >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '24 months'
  GROUP BY DATE_TRUNC('month', event_time), event_type
  ORDER BY month, event_type;

SELECT
      vehicle_id,
      COUNT(DISTINCT json_extract_path_text(content, 'model')) AS distinct_models
  FROM auto.tbl_auto_quotation_event
  WHERE event_type = 'CAPVehicleDetailsRecorded'
    AND vehicle_id IS NOT NULL
  GROUP BY vehicle_id
  HAVING COUNT(DISTINCT json_extract_path_text(content, 'model')) > 1;



SELECT
      SUM(vaps_amount) AS total_vaps_amount_of_credit
  FROM (
      SELECT
          aggregate_id,
          SUM(CASE
              WHEN event_type = 'VapsDetailsCalculated'
              THEN CAST(json_extract_path_text(content, 'vaps_amount_of_credit') AS DECIMAL(18,2))
              ELSE 0
          END) AS vaps_amount,
          COUNT(CASE WHEN event_type = 'ProposalApprovedForPayout' THEN 1 END) AS has_payout
      FROM auto.tbl_auto_quotation_event
      WHERE event_type IN ('VapsDetailsCalculated', 'ProposalApprovedForPayout')
        AND event_time >= CURRENT_DATE - INTERVAL '365 days'
      GROUP BY aggregate_id
      HAVING COUNT(CASE WHEN event_type = 'ProposalApprovedForPayout' THEN 1 END) > 0
         AND COUNT(CASE WHEN event_type = 'VapsDetailsCalculated' THEN 1 END) > 0
  ) sub;

WITH event_counts AS (
    SELECT
        aggregate_id,
        COUNT(*) AS event_count
    FROM auto.tbl_auto_quotation_event
    WHERE event_time >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month'
      AND event_time < DATE_TRUNC('month', CURRENT_DATE)
    GROUP BY aggregate_id
)
SELECT
    AVG(event_count) AS avg_events_per_application
FROM event_counts;

SELECT
    COUNT(DISTINCT aggregate_id) AS application_count
FROM auto.tbl_auto_quotation_event
WHERE event_type = 'RefiVehiclePreapprovalRequested'
  AND event_time >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '6 months';


SELECT
    SUM(CAST(json_extract_path_text(content, 'loan_amount') AS NUMERIC)) AS total_loan_amount
FROM auto.tbl_auto_quotation_event
WHERE event_type = 'ProposalApprovedForPayout'
  AND event_time >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month';

WITH filtered_events AS (
    SELECT
        aggregate_id,
        event_type,
        event_time,
        json_extract_path_text(content, 'loan_amount') AS loan_amount
    FROM auto.tbl_auto_quotation_event
    WHERE event_type IN ('ProposalApproved', 'ProposalApprovedForPayout')
),
last_proposal_approved AS (
    SELECT
        aggregate_id,
        loan_amount,
        ROW_NUMBER() OVER (PARTITION BY aggregate_id ORDER BY event_time DESC) AS row_num
    FROM filtered_events
    WHERE event_type = 'ProposalApproved'
),
applications_with_both_events AS (
    SELECT DISTINCT
        f.aggregate_id
    FROM filtered_events f
    WHERE f.event_type = 'ProposalApprovedForPayout'
      AND EXISTS (
          SELECT 1
          FROM filtered_events f2
          WHERE f2.aggregate_id = f.aggregate_id
            AND f2.event_type = 'ProposalApproved'
      )
)
SELECT
    lpa.aggregate_id,
    CAST(lpa.loan_amount AS NUMERIC) AS loan_amount
FROM last_proposal_approved lpa
JOIN applications_with_both_events ab ON lpa.aggregate_id = ab.aggregate_id
WHERE lpa.row_num = 1;

SELECT
    version_number + 1 AS event_count,
    COUNT(*) AS num_aggregates
FROM (
    SELECT
        aggregate_id,
        MAX(version_number) AS version_number
    FROM auto.tbl_auto_quotation_event
    GROUP BY aggregate_id
) agg
GROUP BY version_number
ORDER BY version_number;

SELECT
      agg.event_count_bucket,
      COUNT(*) AS num_events_last_7_days
  FROM auto.tbl_auto_quotation_event e
  JOIN (
      SELECT
          aggregate_id,
          CASE
              WHEN COUNT(*) <= 10 THEN '1-10'
              WHEN COUNT(*) <= 25 THEN '11-25'
              WHEN COUNT(*) <= 50 THEN '26-50'
              WHEN COUNT(*) > 50 THEN '51+'
          END AS event_count_bucket
      FROM auto.tbl_auto_quotation_event
      GROUP BY aggregate_id
  ) agg ON e.aggregate_id = agg.aggregate_id
  WHERE e.event_time > DATEADD(day, -7, GETDATE())
  GROUP BY agg.event_count_bucket;
/**
  1-10,1381155
11-25,12746442
51+,84854
26-50,148789

 */


 with filtered_events AS (
    SELECT
        aggregate_id,
        event_type
    FROM auto.tbl_auto_quotation_event
    WHERE event_type IN ('ProposalApprovedForPayout', 'VapsDetailsCalculated')
      AND event_time >= CURRENT_DATE - INTERVAL '30 days'
),
applications_with_both_events AS (
    SELECT
        aggregate_id
    FROM filtered_events
    GROUP BY aggregate_id
    HAVING COUNT(DISTINCT event_type) = 2
)
SELECT
    aggregate_id
FROM applications_with_both_events;

WITH daily_event_counts AS (
    SELECT
        DATE(event_time) AS event_date,
        COUNT(*) AS event_count
    FROM auto.tbl_auto_quotation_event
    WHERE event_type = 'ApplicationStarted'
      AND event_time >= CURRENT_DATE - INTERVAL '30 days'
      AND EXTRACT(DOW FROM event_time) NOT IN (0, 6) -- Exclude weekends
    GROUP BY DATE(event_time)
)
SELECT
    SUM(event_count) AS total_events,
    AVG(event_count) AS average_per_day,
    MAX(event_count) AS peak_events_per_day
FROM daily_event_counts;

WITH applications_with_all_events AS (
    SELECT
        aggregate_id
    FROM auto.tbl_auto_quotation_event
    WHERE event_type IN ('ProposalApproved', 'EligibilityQuoteRequested', 'CallScheduled')
      AND event_time >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY aggregate_id
    HAVING COUNT(DISTINCT event_type) = 3
)
SELECT
    a.aggregate_id,
    json_extract_path_text(e.content, 'product_type') AS product_type
FROM applications_with_all_events a
JOIN auto.tbl_auto_quotation_event e
    ON e.aggregate_id = a.aggregate_id
    AND e.event_type = 'ProposalApproved'
    AND e.event_time >= CURRENT_DATE - INTERVAL '7 days'
WHERE json_extract_path_text(e.content, 'product_type') = 'PCP';
