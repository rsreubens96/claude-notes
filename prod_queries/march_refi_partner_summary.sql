WITH target_applications AS (
    SELECT aggregate_id
    FROM auto.tbl_auto_quotation_event
    WHERE event_type IN ('ApplicationStarted', 'ProposalApprovedForPayout', 'ProposalRequested')
      AND event_time >= '2026-03-01'
      AND event_time < '2026-04-01'
    GROUP BY aggregate_id
    HAVING COUNT(DISTINCT event_type) = 3
),
refi_applications AS (
    SELECT
        t.aggregate_id,
        e.referrer_id AS partner
    FROM target_applications t
    JOIN auto.tbl_auto_quotation_event e
        ON e.aggregate_id = t.aggregate_id
        AND e.event_type = 'ApplicationStarted'
    WHERE e.referrer_id IN ('ABClearScoreRefi', 'ABMotivRefi', 'ABHDEXPRefi')
),
ranked_proposals AS (
    SELECT
        r.aggregate_id,
        r.partner,
        CAST(json_extract_path_text(e.content, 'loan_amount') AS DECIMAL(18,2)) AS loan_amount,
        ROW_NUMBER() OVER (PARTITION BY r.aggregate_id ORDER BY e.event_time DESC) AS row_num
    FROM refi_applications r
    JOIN auto.tbl_auto_quotation_event e
        ON e.aggregate_id = r.aggregate_id
        AND e.event_type = 'ProposalRequested'
),
last_proposal_requested AS (
    SELECT aggregate_id, partner, loan_amount
    FROM ranked_proposals
    WHERE row_num = 1
)
SELECT
    partner,
    COUNT(*) AS application_count,
    SUM(loan_amount) AS total_loan_amount
FROM last_proposal_requested
GROUP BY partner
ORDER BY partner;
