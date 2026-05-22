SELECT * FROM auto.tbl_auto_quotation_event


-- Data Source: Amazon Redshift Serverless - production Database: production External Schema: auto External Table: tbl_auto_quotation_event
-- -- auto-generated definition
-- create external table auto.tbl_auto_quotation_event
--     (
--     id integer,
--     correlation_id varchar(40),
--     aggregate_id varchar(40),
--     aggregate_type varchar(100),
--     event_type varchar(100),
--     version_number integer,
--     sequence_number integer,
--     content varchar(65535),
--     event_time timestamp,
--     inserted_date_time timestamp,
--     eligibility_id varchar(40),
--     eligibility_correlation_id varchar(40),
--     proposal_id varchar(40),
--     vehicle_id varchar(40),
--     referrer_id varchar(20)
--     )
--     row format serde ???
-- stored as
-- inputformat ???
-- outputformat ???
-- location 'local:datashare_dwh';
--  Show table preview

WITH refi_applications AS (
      SELECT DISTINCT aggregate_id
      FROM auto.tbl_auto_quotation_event
      WHERE event_type = 'ApplicationStarted'
        AND referrer_id IN ('ABClearScoreRefi', 'ABMotivRefi', 'ABHDEXPRefi')
        AND event_time >= '2026-03-01'
        AND event_time < '2026-03-27'
  )
  SELECT COUNT(*) AS application_count
  FROM refi_applications r;

WITH refi_applications AS (
      SELECT DISTINCT aggregate_id
      FROM auto.tbl_auto_quotation_event
      WHERE event_type = 'ApplicationStarted'
        AND referrer_id IN ('ABClearScoreRefi', 'ABMotivRefi', 'ABHDEXPRefi')
        AND event_time >= '2026-03-01'
        AND event_time < '2026-03-27'
  ),
  payout_approved AS (
      SELECT e.aggregate_id, e.proposal_id
      FROM refi_applications r
      JOIN auto.tbl_auto_quotation_event e
          ON e.aggregate_id = r.aggregate_id
          AND e.event_type = 'ProposalApprovedForPayout'
  )
  SELECT SUM(CAST(json_extract_path_text(e.content, 'loan_amount') AS NUMERIC)) AS total_loan_amount
  FROM payout_approved p
  JOIN auto.tbl_auto_quotation_event e
      ON e.aggregate_id = p.aggregate_id
      AND e.event_type = 'ProposalRequested'
      AND e.proposal_id = p.proposal_id;
WITH refi_applications AS (
      SELECT DISTINCT aggregate_id
      FROM auto.tbl_auto_quotation_event
      WHERE event_type = 'ApplicationStarted'
        AND json_extract_path_text(content, 'referrer_id') IN ('ABOrganic', 'ABClearScoreRefi', 'ABMotivRefi',
  'ABHDEXPRefi')
        AND event_time >= '2026-02-01'
        AND event_time < '2026-03-01'
  )
  SELECT COUNT(*) AS application_count
  FROM refi_applications r
  WHERE EXISTS (
      SELECT 1
      FROM auto.tbl_auto_quotation_event e
      WHERE e.aggregate_id = r.aggregate_id
        AND e.event_type = 'RefiVehiclePreapprovalRequested'
  )
  AND EXISTS (
      SELECT 1
      FROM auto.tbl_auto_quotation_event e
      WHERE e.aggregate_id = r.aggregate_id
        AND e.event_type = 'EligibilityQuoteApproved'
  );

SELECT * from auto.tbl_auto_quotation_event WHERE event_type = 'VehicleReportFilePulled' LIMIT 1;
SELECT DISTINCT aqe.aggregate_id
  FROM auto.tbl_auto_quotation_event aqe
  WHERE NOT EXISTS (
      SELECT 1
      FROM auto.tbl_auto_quotation_event aqe2
      WHERE aqe2.aggregate_id = aqe.aggregate_id
      AND aqe2.event_type IN (
          'ApplicationAnonymisationScheduleSet',
          'EligibilityQuoteFailed',
          'EligibilityQuoteDeclined'
      )
  )
  AND aqe.event_time >= CURRENT_DATE - INTERVAL '30 days';

SELECT DISTINCT a.aggregate_id
  FROM auto.tbl_auto_quotation_event a
  LEFT JOIN auto.tbl_auto_quotation_event b
      ON a.aggregate_id = b.aggregate_id
      AND b.event_type IN (
          'ApplicationAnonymisationScheduleSet',
          'EligibilityQuoteFailed',
          'EligibilityQuoteDeclined'
      )
  WHERE b.aggregate_id IS NULL
  AND a.event_time >= CURRENT_DATE - INTERVAL '30 days';

SELECT aggregate_id, event_type
  FROM auto.tbl_auto_quotation_event
  WHERE aggregate_id = '152F21BA-58A0-463B-BC32-F0800D8B9893';

SELECT
      REGEXP_SUBSTR(s.content, '"referrer_id":"([^"]+)"', 1, 1, 'e') AS referrer_id,
      COUNT(*) AS total
  FROM auto.tbl_auto_quotation_event pf
  JOIN auto.tbl_auto_quotation_event s
      ON pf.aggregate_id = s.aggregate_id
      AND s.event_type = 'ApplicationStarted'
  WHERE pf.event_type = 'ProposalFailed'
  AND pf.content LIKE '%Unable to find ApplicantId%'
  AND pf.event_time >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY 1
  ORDER BY 2 DESC;

WITH ranked_invoices AS (
      SELECT
          aggregate_id,
          json_extract_path_text(content, 'quote_id') AS proposal_id,
          json_extract_path_text(content, 'vat_amount') AS vat_amount,
          ROW_NUMBER() OVER (PARTITION BY aggregate_id ORDER BY event_time DESC) AS rn
      FROM auto.tbl_auto_quotation_event
      WHERE event_type = 'InvoiceGenerated'
        AND event_time >= '2026-02-01'
        AND event_time < '2026-03-01'
  )
  SELECT
      proposal_id,
      CAST(vat_amount AS DECIMAL(18, 2)) AS vat_amount
  FROM ranked_invoices
  WHERE rn = 1
    AND CAST(vat_amount AS DECIMAL(18, 2)) != 0;
SELECT DISTINCT aggregate_id
  FROM auto.tbl_auto_quotation_event
  WHERE event_time >= CURRENT_DATE - INTERVAL '30 days'

  EXCEPT

  SELECT DISTINCT aggregate_id
  FROM auto.tbl_auto_quotation_event
  WHERE event_type IN (
      'ApplicationAnonymisationScheduleSet',
      'EligibilityQuoteFailed',
      'EligibilityQuoteDeclined'
  );

SELECT
      REGEXP_SUBSTR(s.content, '"referrer_id":"([^"]+)"', 1, 1, 'e') AS referrer_id,
      COUNT(*) AS total
  FROM auto.tbl_auto_quotation_event pf
  JOIN auto.tbl_auto_quotation_event s
      ON pf.aggregate_id = s.aggregate_id
      AND s.event_type = 'ApplicationStarted'
  WHERE pf.event_type = 'ProposalFailed'
  AND pf.content LIKE '%Unable to find ApplicantId%'
  AND pf.event_time >= CURRENT_DATE - INTERVAL '30 days'
  GROUP BY 1
  ORDER BY 2 DESC;




select * from auto.tbl_auto_quotation_event WHERE aggregate_id = '79878cdb-846d-4146-a805-907907b33cac';
SELECT * FROM auto.tbl_auto_quotation_event WHERE event_type = 'ProposalApprovedForPayout' AND event_time >= CURRENT_DATE - INTERVAL '30 days' LIMIT 10;



SELECT decline_reasons FROM auto.tbl_auto_quote_declined_analytics WHERE decline_reasons LIKE '%Could not retrieve dvla data.%' OR decline_reasons LIKE '%Could not retrieve future valuation.%' AND event_time >= CURRENT_DATE - INTERVAL '30 days';

-- Basic template for querying applications that have a combination of events
SELECT SUM(aggregate_id)
FROM auto.tbl_auto_quotation_event
WHERE (
    (event_type = 'ApplicationStarted' AND json_extract_path_text(content, 'referrer_id') = 'ABClearScoreRefi')
    OR (event_type = 'EligibilityQuoteRequested' AND content LIKE '%HP%')
--     OR (event_type = 'ProposalApprovedForPayout')
)
AND content NOT LIKE '%REFI_HP%'
AND event_time >= CURRENT_DATE - INTERVAL '30 days'
-- GROUP BY aggregate_id
HAVING
    COUNT(CASE WHEN event_type = 'ApplicationStarted' AND json_extract_path_text(content, 'referrer_id') = 'ABBorrowingPower' THEN 1 END) > 0
    AND COUNT(CASE WHEN event_type = 'EligibilityQuoteRequested' AND content LIKE '%HP%' THEN 1 END) > 0;
--     AND COUNT(CASE WHEN event_type = 'ProposalApprovedForPayout' THEN 1 END) > 0;

-- Refi eligibility
SELECT aggregate_id, MAX(event_time) AS last_event_time
FROM auto.tbl_auto_quotation_event
WHERE (
    (event_type = 'ApplicationStarted' AND json_extract_path_text(content, 'referrer_id') = 'ABOrganic')
    OR (event_type = 'RefiVehiclePreapprovalRequested')
--         OR (event_type = 'EligibilityQuoteApproved')
)
AND event_time >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY aggregate_id
HAVING
    COUNT(CASE WHEN event_type = 'ApplicationStarted' AND json_extract_path_text(content, 'referrer_id') = 'ABOrganic' THEN 1 END) > 0
    AND COUNT(CASE WHEN event_type = 'RefiVehiclePreapprovalRequested' THEN 1 END) > 0
--     AND COUNT(CASE WHEN event_type = 'EligibilityQuoteApproved' THEN 1 END) > 0;

SELECT * FROM auto.tbl_auto_quotation_event WHERE aggregate_id='9add9c07-a0d3-4776-af8e-ae2135871601';

-- This query retrieves distinct aggregate_id values where a specific member_id is associated with an ApplicationStarted event,
-- filtered by a specific referrer_id and limited to events occurring within the last 30 days.
SELECT DISTINCT t1.aggregate_id
FROM auto.tbl_auto_quotation_event t1
JOIN auto.tbl_auto_quotation_event t2
  ON t1.aggregate_id = t2.aggregate_id
WHERE
  json_extract_path_text(t1.content, 'member_id') = '52a11206-3ef5-ee11-b946-005056990747'
  AND t2.event_type = 'ApplicationStarted'
  AND json_extract_path_text(t2.content, 'referrer_id') = 'ABOrganic'
  AND t1.event_time >= CURRENT_DATE - INTERVAL '30 days'
  AND t2.event_time >= CURRENT_DATE - INTERVAL '30 days';

WITH agg AS (
    SELECT
        aggregate_id AS app_id,
        MAX(event_time) AS last_event_time,
        MAX(json_extract_path_text(content, 'referrer_id')) AS referrer_id,

        -- Eligibility stages
        MAX(CASE WHEN event_type = 'EligibilityQuoteApproved' THEN 1 ELSE 0 END) AS has_el_approved,
--         MAX(CASE WHEN event_type = 'EligibilityQuoteDeclined' THEN 1 ELSE 0 END) AS has_el_declined,
        MAX(CASE WHEN event_type = 'EligibilityQuoteFailed'   THEN 1 ELSE 0 END) AS has_el_failed,

        -- Proposal / later stages
        MAX(CASE WHEN event_type = 'ProposalApprovedForPayout'       THEN 1 ELSE 0 END) AS has_paid_out,
        MAX(CASE WHEN event_type = 'ProposalSubmissionSucceeded'     THEN 1 ELSE 0 END) AS has_submission_succeeded,
        MAX(CASE WHEN event_type = 'CallScheduled'                   THEN 1 ELSE 0 END) AS has_call_scheduled,
        MAX(CASE WHEN event_type = 'ProposalApproved'                THEN 1 ELSE 0 END) AS has_proposal_approved,
        MAX(CASE WHEN event_type = 'ProposalDeclined'                THEN 1 ELSE 0 END) AS has_proposal_declined,
        MAX(CASE WHEN event_type = 'ProposalFailed'                  THEN 1 ELSE 0 END) AS has_proposal_failed,
        MAX(CASE WHEN event_type = 'RefiVehiclePreapprovalRequested' THEN 1 ELSE 0 END) AS has_refi_preapproval,
        MAX(CASE WHEN json_extract_path_text(content, 'referrer_id') = 'ABOrganic'
                 THEN 1 ELSE 0 END) AS has_aborganic
    FROM auto.tbl_auto_quotation_event
    WHERE event_time >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY aggregate_id
),

ranked AS (
    SELECT
        app_id,
        GREATEST(
            -- furthest / latest stage = highest rank
            CASE WHEN has_paid_out = 1
                  AND has_refi_preapproval = 1
                  AND has_aborganic = 1 THEN 9 ELSE 0 END,
            CASE WHEN has_submission_succeeded = 1
                  AND has_refi_preapproval = 1
                  AND has_aborganic = 1 THEN 8 ELSE 0 END,
            CASE WHEN has_call_scheduled = 1
                  AND has_refi_preapproval = 1
                  AND has_aborganic = 1 THEN 7 ELSE 0 END,
            CASE WHEN has_proposal_approved = 1
                  AND has_refi_preapproval = 1
                  AND has_aborganic = 1 THEN 6 ELSE 0 END,
            CASE WHEN has_proposal_declined = 1
                  AND has_refi_preapproval = 1
                  AND has_aborganic = 1 THEN 5 ELSE 0 END,
            CASE WHEN has_proposal_failed = 1
                  AND has_refi_preapproval = 1
                  AND has_aborganic = 1 THEN 4 ELSE 0 END,
            CASE WHEN has_el_approved = 1
                  AND has_aborganic = 1 THEN 3 ELSE 0 END,
--             CASE WHEN has_el_declined = 1
--                   AND has_aborganic = 1 THEN 2 ELSE 0 END,
            CASE WHEN has_el_failed = 1
                  AND has_aborganic = 1 THEN 1 ELSE 0 END
        ) AS stage_rank
    FROM agg
),

classified AS (
    SELECT
        app_id,
        CASE stage_rank
            WHEN 9 THEN 'Paid out'
            WHEN 8 THEN 'Esigned'
            WHEN 7 THEN 'Call Scheduled'
            WHEN 6 THEN 'Proposal Approved'
            WHEN 5 THEN 'Proposal Declined'
            WHEN 4 THEN 'Proposal Failed'
            WHEN 3 THEN 'Eligibility Approved'
            WHEN 2 THEN 'Eligibility Declined'
            WHEN 1 THEN 'Eligibility Failed'
            ELSE 'UNKNOWN'
        END AS stage
    FROM ranked
)

SELECT
    stage,
    COUNT(DISTINCT app_id) AS applications
FROM classified
WHERE stage <> 'UNKNOWN'
GROUP BY stage
ORDER BY
    CASE stage
        WHEN 'Eligibility Approved'  THEN 1
        WHEN 'Eligibility Declined'  THEN 2
        WHEN 'Eligibility Failed'    THEN 3
        WHEN 'Proposal Approved'     THEN 4
        WHEN 'Proposal Declined'     THEN 5
        WHEN 'Proposal Failed'       THEN 6
        WHEN 'Call Scheduled'        THEN 7
        WHEN 'Esigned'               THEN 8
        WHEN 'Paid out'              THEN 9
        ELSE 99
    END;

SELECT
    DATE_TRUNC('month', event_time) AS month,
    CASE
        WHEN event_type IN ('CAPVehicleDetailsRecorded', 'CAPVehicleDetailsFetchFailed') THEN 'CAP Vehicle Details'
        WHEN event_type IN ('FutureValuationFetched', 'FutureValuationFetchFailed') THEN 'Future Valuation'
    END AS event_category,
    COUNT(*) AS event_count
FROM auto.tbl_auto_quotation_event
WHERE event_type IN (
        'CAPVehicleDetailsRecorded',
        'CAPVehicleDetailsFetchFailed',
        'FutureValuationFetched',
        'FutureValuationFetchFailed'
    )
    AND event_time >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '24 months'
GROUP BY DATE_TRUNC('month', event_time), event_category
ORDER BY month, event_category;

SELECT
    DATE_TRUNC('month', event_time) AS month,
    CASE
        WHEN event_type IN ('CAPVehicleDetailsRecorded', 'FutureValuationFetched') THEN 'Success'
        WHEN event_type IN ('CAPVehicleDetailsFetchFailed', 'FutureValuationFetchFailed') THEN 'Failure'
    END AS event_status,
    event_type,
    COUNT(*) AS event_count
FROM auto.tbl_auto_quotation_event
WHERE event_type IN (
        'CAPVehicleDetailsRecorded',
        'CAPVehicleDetailsFetchFailed',
        'FutureValuationFetched',
        'FutureValuationFetchFailed'
    )
    AND event_time >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '24 months'
GROUP BY DATE_TRUNC('month', event_time), event_status, event_type
ORDER BY month, event_status, event_type;


SELECT DISTINCT event_type
FROM auto.tbl_auto_quotation_event
WHERE event_type IN ('CapVehicleDetailsRecorded', 'CapVehicleDetailsFetchFailed');

SELECT event_type, event_time
FROM auto.tbl_auto_quotation_event
WHERE event_type IN ('CapVehicleDetailsRecorded', 'CapVehicleDetailsFetchFailed')
  AND event_time >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '12 months';

WITH refi_apps AS (
    SELECT aggregate_id
    FROM auto.tbl_auto_quotation_event
    WHERE (
        (event_type = 'ApplicationStarted' AND json_extract_path_text(content, 'referrer_id') = 'ABOrganic')
            OR event_type = 'RefiVehiclePreapprovalRequested'
            OR event_type IN (
                              'EligibilityQuoteApproved',
                              'EligibilityTransferred',
                              'ProposalApproved',
                              'ProposalDeclined',
                              'CallScheduled',
                              'ProposalFailed',
                              'EligibilityQuoteDeclined'
            )
        )
      AND event_time >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY aggregate_id
    HAVING
        COUNT(CASE WHEN event_type = 'ApplicationStarted' AND json_extract_path_text(content, 'referrer_id') = 'ABOrganic' THEN 1 END) > 0
       AND COUNT(CASE WHEN event_type = 'RefiVehiclePreapprovalRequested' THEN 1 END) > 0
),
     ranked_events AS (
         SELECT
             e.aggregate_id,
             e.event_type,
             ROW_NUMBER() OVER (PARTITION BY e.aggregate_id ORDER BY e.event_time DESC) AS rn
         FROM auto.tbl_auto_quotation_event e
                  JOIN refi_apps r ON e.aggregate_id = r.aggregate_id
         WHERE e.event_type IN (
                                'EligibilityQuoteApproved',
                                'EligibilityTransferred',
                                'ProposalApproved',
                                'ProposalDeclined',
                                'CallScheduled',
                                'ProposalFailed',
                                'EligibilityQuoteDeclined'
             )
     ),
     latest_events AS (
         SELECT aggregate_id, event_type AS latest_event
         FROM ranked_events
         WHERE rn = 1
     )
SELECT latest_event, COUNT(*) AS application_count
FROM latest_events
GROUP BY latest_event
UNION ALL
SELECT 'TOTAL APPLICATIONS', COUNT(*) FROM refi_apps
ORDER BY application_count DESC;

SELECT
    DATE_TRUNC('month', event_time) AS month,
    CASE
        WHEN event_type IN ('CAPVehicleDetailsRecorded', 'CAPVehicleDetailsFetchFailed') THEN 'CAP Vehicle Details'
        WHEN event_type IN ('FutureValuationFetched', 'FutureValuationFetchFailed') THEN 'Future Valuation'
    END AS event_category,
    COUNT(*) AS event_count
FROM auto.tbl_auto_quotation_event
WHERE event_type IN (
        'CAPVehicleDetailsRecorded',
        'CAPVehicleDetailsFetchFailed',
        'FutureValuationFetched',
        'FutureValuationFetchFailed'
    )
    AND event_time >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '12 months'
GROUP BY DATE_TRUNC('month', event_time), event_category
ORDER BY month, event_category;




WITH agg AS (
    SELECT
        aggregate_id,
        COUNT(CASE WHEN event_type = 'EsignTransferRecorded' THEN 1 END) AS esign_transfer_count,
        COUNT(CASE WHEN event_type = 'ProposalSubmissionRequested' THEN 1 END) AS submission_succeeded_count,
        COUNT(CASE WHEN event_type = 'NationalityRecorded' THEN 1 END) AS nationality_recorded_count,
        MAX(event_time) AS last_event_time
    FROM auto.tbl_auto_quotation_event
    WHERE event_time >= CURRENT_DATE - INTERVAL '90 days'
    GROUP BY aggregate_id
)
SELECT
    aggregate_id,
    esign_transfer_count,
    nationality_recorded_count,
    last_event_time
FROM agg
WHERE esign_transfer_count > 3
  AND submission_succeeded_count = 0

ORDER BY esign_transfer_count DESC, last_event_time DESC;

WITH all_esign AS (
    SELECT
        aggregate_id,
        COUNT(CASE WHEN event_type = 'EsignTransferRecorded' THEN 1 END) AS esign_count,
        COUNT(CASE WHEN event_type = 'ProposalSubmissionSucceeded' THEN 1 END) AS submission_succeeded_count,
        COUNT(CASE WHEN event_type = 'NationalityRecorded' THEN 1 END) AS nationality_count
    FROM auto.tbl_auto_quotation_event
    WHERE event_time >= CURRENT_DATE - INTERVAL '30 days'   -- adjust if needed
    GROUP BY aggregate_id
),

classified AS (
    SELECT
        CASE
            WHEN nationality_count >= 1
                 AND esign_count > 2
                 AND submission_succeeded_count = 0
                THEN 'ESIGN_ISSUE'

            WHEN submission_succeeded_count >= 1
                THEN 'ESIGN_SUCCESS'

            ELSE 'OTHER_ESIGN'
        END AS esign_status
    FROM all_esign
    WHERE esign_count >= 1     -- only consider apps that actually reached esign
)

SELECT
    esign_status,
    COUNT(*) AS application_count
FROM classified
WHERE esign_status IN ('ESIGN_ISSUE', 'ESIGN_SUCCESS')   -- exclude OTHER_ESIGN
GROUP BY esign_status
ORDER BY
    CASE esign_status
        WHEN 'ESIGN_SUCCESS' THEN 1
        WHEN 'ESIGN_ISSUE'   THEN 2
    END;


WITH all_esign AS (
    SELECT
        aggregate_id,
        COUNT(CASE WHEN event_type = 'EsignTransferRecorded' THEN 1 END) AS esign_count,
        COUNT(CASE WHEN event_type = 'ProposalSubmissionSucceeded' THEN 1 END) AS submission_succeeded_count,
        COUNT(CASE WHEN event_type = 'NationalityRecorded' THEN 1 END) AS nationality_count,
        MAX(
            CASE
                WHEN event_type = 'ApplicationStarted'
                THEN json_extract_path_text(content, 'referrer_id')
            END
        ) AS referrer_id
    FROM auto.tbl_auto_quotation_event
    WHERE event_time >= CURRENT_DATE - INTERVAL '30 days'   -- adjust if needed
    GROUP BY aggregate_id
),

classified AS (
    SELECT
        CASE
                 WHEN esign_count > 4
                 AND submission_succeeded_count = 0
                THEN 'ESIGN_ISSUE'

            WHEN submission_succeeded_count >= 1
                THEN 'ESIGN_SUCCESS'

            ELSE 'OTHER_ESIGN'
        END AS esign_status
    FROM all_esign
    WHERE esign_count >= 1
      AND (referrer_id IS NULL OR referrer_id <> 'ABClearScore')  -- exclude ABClearScore
)

SELECT
    esign_status,
    COUNT(*) AS application_count
FROM classified
WHERE esign_status IN ('ESIGN_ISSUE', 'ESIGN_SUCCESS')   -- exclude OTHER_ESIGN
GROUP BY esign_status
ORDER BY
    CASE esign_status
        WHEN 'ESIGN_SUCCESS' THEN 1
        WHEN 'ESIGN_ISSUE'   THEN 2
    END;

WITH base AS (
    SELECT
        aggregate_id,
        DATE_TRUNC('month', event_time) AS month_bucket,
        COUNT(CASE WHEN event_type = 'EsignTransferRecorded' THEN 1 END) AS esign_count,
        COUNT(CASE WHEN event_type = 'ProposalSubmissionSucceeded' THEN 1 END) AS submission_succeeded_count,
        COUNT(CASE WHEN event_type = 'NationalityRecorded' THEN 1 END) AS nationality_count
    FROM auto.tbl_auto_quotation_event
    WHERE event_time >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '3 months'
    GROUP BY aggregate_id, DATE_TRUNC('month', event_time)
),

classified AS (
    SELECT
        month_bucket,
        CASE
            WHEN esign_count > 2
                 AND nationality_count = 0
                 AND submission_succeeded_count = 0
                THEN 'ISSUE_1_MULTIPLE_ESIGN_NO_PROGRESS'

            WHEN esign_count > 2
                 AND nationality_count >= 1
                 AND submission_succeeded_count = 0
                THEN 'ISSUE_2_MULTIPLE_ESIGN_WITH_NATIONALITY'

            WHEN submission_succeeded_count >= 1
                THEN 'ESIGN_SUCCESS'

            ELSE 'OTHER'
        END AS category
    FROM base
    WHERE esign_count >= 1
)

SELECT
    TO_CHAR(month_bucket, 'YYYY-MM') AS month,
    category,
    COUNT(*) AS application_count
FROM classified
WHERE category <> 'OTHER'
GROUP BY month_bucket, category
ORDER BY month_bucket, category;

SELECT
      event_type,
      COUNT(DISTINCT vehicle_id) AS unique_vehicles
  FROM auto.tbl_auto_quotation_event
  WHERE event_type IN (
      'CAPVehicleDetailsRecorded',
      'CAPVehicleDetailsFetchFailed',
      'FutureValuationFetched',
      'FutureValuationFetchFailed'
  )
  GROUP BY event_type
  ORDER BY event_type;

  SELECT
      DATE_TRUNC('month', event_time) AS month,
      event_type,
      COUNT(DISTINCT COALESCE(vehicle_id, aggregate_id)) AS unique_vehicles
  FROM auto.tbl_auto_quotation_event
  WHERE event_type IN (
      'CAPVehicleDetailsRecorded',
      'CAPVehicleDetailsFetchFailed',
      'FutureValuationFetched',
      'FutureValuationFetchFailed'
  )
  AND event_time >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '12 months'
  GROUP BY DATE_TRUNC('month', event_time), event_type
  ORDER BY month, event_type;

SELECT
    aggregate_id,
    COUNT(*) AS future_valuation_count
FROM auto.tbl_auto_quotation_event
WHERE event_type = 'FutureValuationFetched'
AND  event_time >= CURRENT_DATE - INTERVAL '30 days'   -- adjust if needed

GROUP BY aggregate_id
HAVING COUNT(*) > 1
ORDER BY future_valuation_count DESC;








