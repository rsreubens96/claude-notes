-- eligibilitytransferreds
SELECT COUNT(DISTINCT aggregate_id)
  FROM auto.tbl_auto_quotation_event
  WHERE event_type = 'EligibilityTransferred'
    AND json_extract_path_text(content, 'reason') = 'Transfer from aggregator'
    AND event_time >= '2026-02-01'
    AND event_time < '2026-04-01'
    AND EXISTS (
        SELECT 1 FROM auto.tbl_auto_quotation_event b
        WHERE b.aggregate_id = auto.tbl_auto_quotation_event.aggregate_id
          AND b.event_type = 'RefiBorrowingPowerRequested'
    );
WITH refi_base AS (
      SELECT DISTINCT aggregate_id
      FROM auto.tbl_auto_quotation_event
      WHERE event_type = 'RefiBorrowingPowerRequested'
  )
  SELECT
      e.aggregate_id,
      json_extract_path_text(e.content, 'member_id')                                   AS member_id,
      e.event_time                                                                      AS declined_at,
      json_extract_array_element_text(json_extract_path_text(e.content, 'reasons'), 0) AS primary_decline_reason,
      json_extract_array_element_text(json_extract_path_text(e.content, 'reasons'), 1) AS secondary_decline_reason,
      json_extract_path_text(e.content, 'triggered_rules')                             AS triggered_rules,
      json_extract_path_text(e.content, 'product_type')                                AS product_type,
      json_extract_path_text(e.content, 'decisioning_engine')                          AS decisioning_engine
  FROM auto.tbl_auto_quotation_event e
  INNER JOIN refi_base b ON e.aggregate_id = b.aggregate_id
  WHERE e.event_type = 'ProposalDeclined'
    AND e.event_time >= CURRENT_DATE - INTERVAL '30 days';

drop table if exists #people_with_bp;
create temp table #people_with_bp as
(select upper(member_id) as member_id
 from aurora_borrowing_power.tbl_member_detail
 where subscription_status=2);

WITH refi_declined AS (
      SELECT
          e.aggregate_id,
          json_extract_path_text(e.content, 'member_id')                                   AS member_id,
          json_extract_path_text(e.content, 'risk_market')                                 AS risk_market,
          json_extract_array_element_text(json_extract_path_text(e.content, 'reasons'), 0) AS primary_decline_reason,
          json_extract_array_element_text(json_extract_path_text(e.content, 'reasons'), 1) AS secondary_decline_reason,
          e.event_time                                                                      AS declined_at
      FROM auto.tbl_auto_quotation_event e
      WHERE e.event_type = 'ProposalDeclined'
        AND e.event_time >= CURRENT_DATE - INTERVAL '30 days'
        AND EXISTS (
            SELECT 1 FROM auto.tbl_auto_quotation_event b
            WHERE b.aggregate_id = e.aggregate_id
              AND b.event_type = 'RefiBorrowingPowerRequested'
        )
  ),
  loan_amounts AS (
      SELECT
          e.aggregate_id,
          json_extract_path_text(e.content, 'finance_request', 'loan_amount') AS loan_amount,
          ROW_NUMBER() OVER (PARTITION BY e.aggregate_id ORDER BY e.event_time ASC) AS row_num
      FROM auto.tbl_auto_quotation_event e
      INNER JOIN refi_declined r ON r.aggregate_id = e.aggregate_id
      WHERE e.event_type = 'ProposalRequested'
        AND e.event_time < r.declined_at
  ),
  aprs AS (
      SELECT
          e.aggregate_id,
          json_extract_path_text(e.content, 'apr') AS apr,
          ROW_NUMBER() OVER (PARTITION BY e.aggregate_id ORDER BY e.event_time ASC) AS row_num
      FROM auto.tbl_auto_quotation_event e
      INNER JOIN refi_declined r ON r.aggregate_id = e.aggregate_id
      WHERE e.event_type = 'APRCalculated'
        AND e.event_time < r.declined_at
  ),
  equifax_file_ids AS (
      SELECT
          upper(member_id)       AS member_id,
          lower(equifax_file_id) AS file_id
      FROM dbt_credit_analytics.tbl_borrowing_main_quotation
      WHERE quote_start_time > DATEADD(month, -2, GETDATE())
        AND upper(member_id) IN (SELECT upper(member_id) FROM refi_declined)
  ),
  cz_data AS (
      SELECT
          upper(f.member_id) AS member_id,
          insi.credit_terms,
          ROW_NUMBER() OVER (PARTITION BY upper(f.member_id) ORDER BY insi.update_date DESC) AS row_num
      FROM credit_reports.tbl_equifax_cr_insight insi
      INNER JOIN equifax_file_ids f ON f.file_id = lower(insi.document_id)
      WHERE insi.account_type = '01'
        AND insi.current_balance <> 0
        AND insi.end_date IS NULL
        AND insi.default_balance = 0
        AND insi.delinquent_date IS NULL
  )
  SELECT
      r.aggregate_id              AS application_id,
      r.member_id,
      l.loan_amount,
      a.apr,
      r.risk_market,
      r.primary_decline_reason,
      r.secondary_decline_reason,
      c.credit_terms
  FROM refi_declined r
  LEFT JOIN loan_amounts l ON l.aggregate_id = r.aggregate_id AND l.row_num = 1
  LEFT JOIN aprs a         ON a.aggregate_id = r.aggregate_id AND a.row_num = 1
  LEFT JOIN cz_data c      ON upper(r.member_id) = c.member_id AND c.row_num = 1;

WITH aggregator_transfers AS (
      SELECT DISTINCT aggregate_id
      FROM auto.tbl_auto_quotation_event
      WHERE event_type = 'CallScheduled'
--         AND json_extract_path_text(content, 'reason') = 'Transfer from aggregator'
        AND event_time >= DATEADD(day, -30, GETDATE())
        AND EXISTS (
            SELECT 1 FROM auto.tbl_auto_quotation_event b
            WHERE b.aggregate_id = auto.tbl_auto_quotation_event.aggregate_id
              AND b.event_type = 'RefiBorrowingPowerRequested'
        )
  ),
  member_ids AS (
      SELECT
          e.aggregate_id,
          json_extract_path_text(e.content, 'member_id') AS member_id,
          ROW_NUMBER() OVER (PARTITION BY e.aggregate_id ORDER BY e.event_time ASC) AS row_num
      FROM auto.tbl_auto_quotation_event e
      INNER JOIN aggregator_transfers t ON t.aggregate_id = e.aggregate_id
      WHERE e.event_type = 'MemberFullyMatched'
  ),
  risk_markets AS (
      SELECT
          e.aggregate_id,
          json_extract_path_text(e.content, 'risk_market') AS risk_market,
          ROW_NUMBER() OVER (PARTITION BY e.aggregate_id ORDER BY e.event_time ASC) AS row_num
      FROM auto.tbl_auto_quotation_event e
      INNER JOIN aggregator_transfers t ON t.aggregate_id = e.aggregate_id
      WHERE e.event_type = 'RiskScorecardOutputsCalculated'
  ),
  aprs AS (
      SELECT
          e.aggregate_id,
          json_extract_path_text(e.content, 'apr') AS apr,
          ROW_NUMBER() OVER (PARTITION BY e.aggregate_id ORDER BY e.event_time ASC) AS row_num
      FROM auto.tbl_auto_quotation_event e
      INNER JOIN aggregator_transfers t ON t.aggregate_id = e.aggregate_id
      WHERE e.event_type = 'APRCalculated'
  ),
cz_data AS (
      SELECT
          upper(member_id)       AS member_id,
          payment_amount,
          company_name,
          current_balance_amount,
          start_date,
          end_date,
          number_of_payments,
          ROW_NUMBER() OVER (PARTITION BY upper(member_id) ORDER BY start_date DESC) AS row_num
      FROM ext_credit_reports.tbl_equifax_cz_payment_history
      WHERE account_type = 'hirePurchase'
        AND create_time > DATEADD(day, -30, GETDATE())
        AND payment_history_age_in_months = 0
        AND upper(member_id) IN (SELECT upper(member_id) FROM member_ids WHERE row_num = 1)
  )
SELECT
      m.aggregate_id         AS application_id,
      m.member_id,
      r.risk_market,
      a.apr,
      c.payment_amount,
      c.company_name,
      c.current_balance_amount,
      c.start_date,
      c.end_date,
      c.number_of_payments
FROM member_ids m
  LEFT JOIN risk_markets r ON r.aggregate_id = m.aggregate_id AND r.row_num = 1
  LEFT JOIN aprs a         ON a.aggregate_id = m.aggregate_id AND a.row_num = 1
  LEFT JOIN cz_data c      ON upper(m.member_id) = c.member_id AND c.row_num = 1
  WHERE m.row_num = 1;

select * from ext_credit_reports.tbl_equifax_cz_payment_history
where upper(member_id)=upper('bd35eed4-b765-f011-84e4-0a34eeeb3329')
  and create_time>dateadd(day,-30,getdate())
  and account_type='hirePurchase'
  and payment_history_age_in_months=0;



WITH aggregator_transfers AS (
      SELECT DISTINCT aggregate_id
      FROM auto.tbl_auto_quotation_event
      WHERE event_type = 'EligibilityTransferred'
        AND json_extract_path_text(content, 'reason') = 'Transfer from aggregator'
        AND event_time >= DATEADD(day, -30, GETDATE())
        AND EXISTS (
            SELECT 1 FROM auto.tbl_auto_quotation_event b
            WHERE b.aggregate_id = auto.tbl_auto_quotation_event.aggregate_id
              AND b.event_type = 'RefiBorrowingPowerRequested'
        )
  ),
  member_ids AS (
      SELECT
          e.aggregate_id,
          json_extract_path_text(e.content, 'member_id') AS member_id,
          ROW_NUMBER() OVER (PARTITION BY e.aggregate_id ORDER BY e.event_time ASC) AS row_num
      FROM auto.tbl_auto_quotation_event e
      INNER JOIN aggregator_transfers t ON t.aggregate_id = e.aggregate_id
      WHERE e.event_type = 'MemberFullyMatched'
  ),
  risk_markets AS (
      SELECT
          e.aggregate_id,
          json_extract_path_text(e.content, 'risk_market') AS risk_market,
          ROW_NUMBER() OVER (PARTITION BY e.aggregate_id ORDER BY e.event_time ASC) AS row_num
      FROM auto.tbl_auto_quotation_event e
      INNER JOIN aggregator_transfers t ON t.aggregate_id = e.aggregate_id
      WHERE e.event_type = 'RiskScorecardOutputsCalculated'
  ),
  aprs AS (
      SELECT
          e.aggregate_id,
          json_extract_path_text(e.content, 'apr') AS apr,
          ROW_NUMBER() OVER (PARTITION BY e.aggregate_id ORDER BY e.event_time ASC) AS row_num
      FROM auto.tbl_auto_quotation_event e
      INNER JOIN aggregator_transfers t ON t.aggregate_id = e.aggregate_id
      WHERE e.event_type = 'APRCalculated'
  ),
  equifax_file_ids AS (
      SELECT
          upper(member_id)       AS member_id,
          lower(equifax_file_id) AS file_id
      FROM dbt_credit_analytics.tbl_borrowing_main_quotation
      WHERE quote_start_time > DATEADD(month, -2, GETDATE())
        AND upper(member_id) IN (SELECT upper(member_id) FROM member_ids WHERE row_num = 1)
  ),
  cz_data AS (
      SELECT
          upper(f.member_id) AS member_id,
          insi.credit_terms,
          ROW_NUMBER() OVER (PARTITION BY upper(f.member_id) ORDER BY insi.update_date DESC) AS row_num
      FROM credit_reports.tbl_equifax_cr_insight insi
      INNER JOIN equifax_file_ids f ON f.file_id = lower(insi.document_id)
      WHERE insi.account_type = '01'
        AND insi.current_balance <> 0
        AND insi.end_date IS NULL
        AND insi.default_balance = 0
        AND insi.delinquent_date IS NULL
  )
  SELECT
      m.aggregate_id  AS application_id,
      m.member_id,
      r.risk_market,
      a.apr,
      c.credit_terms
  FROM member_ids m
  LEFT JOIN risk_markets r ON r.aggregate_id = m.aggregate_id AND r.row_num = 1
  LEFT JOIN aprs a         ON a.aggregate_id = m.aggregate_id AND a.row_num = 1
  LEFT JOIN cz_data c      ON upper(m.member_id) = c.member_id AND c.row_num = 1
  WHERE m.row_num = 1;















--If we wanted to expand pop we could use this which should have CZ file permissions more widely than BP replace above query with this
--Specifically impacting 75k customers in LH
select upper(member_id) as member_id
from mssql_membership.tbl_member_permissions
where permission_id=22
and value=true
*/
drop table if exists #people_with_bp_and_cars;
create temp table #people_with_bp_and_cars as (
with equifax_file_ids as
    (select member_id,
    lower(equifax_file_id) as file_id
    from dbt_credit_analytics.tbl_borrowing_main_quotation
    where quote_start_time>dateadd(month,-2,getdate())
    and member_id in (select member_id from #people_with_bp))

select distinct upper(member_id) as member_id
from credit_reports.tbl_equifax_cr_insight insi
inner join equifax_file_ids f
    on f.file_id = lower(insi.document_id)
where account_type = '01'
and current_balance <> 0
and end_date is null
and default_balance = 0
and delinquent_date is null
and update_date >= dateadd(month,-2,getdate()));

drop table if exists #people_with_bp_and_cars_and_marketing;
create temp table #people_with_bp_and_cars_and_marketing as
(select * from #people_with_bp_and_cars
where upper(member_id) in
(select upper(member_id) from mssql_membership.tbl_member_permissions
where permission_id=15
and value=true));

/*
 If extending pop then may be worth extending this to UPL quotation
 */

drop table if exists #people_with_bp_and_cars_and_marketing_who_are_quoted;
create temp table #people_with_bp_and_cars_and_marketing_who_are_quoted as
(select * from #people_with_bp_and_cars_and_marketing
where upper(member_id) in
(select upper(member_id) from dbt_auto.tbl_auto_main_quotes
where initial_requested_timestamp>dateadd(week ,-1,getdate())
and (approved_at_quote_flag=1 or referred_at_quote_flag=1)
and requested_product='HP'
and channel_referrer_id = 'ABBorrowingPower'));

drop table if exists #people_with_bp_and_cars_and_marketing_who_are_quoted_minus_existing_auto;
create temp table #people_with_bp_and_cars_and_marketing_who_are_quoted_minus_existing_auto as
(select * from #people_with_bp_and_cars_and_marketing_who_are_quoted
where upper(member_id) not in
(select upper(member_id) from dbt_credit_analytics.tbl_month_end
where end_date='2026/01/31'
and product!='UPL'
and coalesce(is_closed_account,0)=0
and coalesce(is_settled,0)=0
and principal_outstanding>0)
and upper(member_id) not in
(select upper(member_id) from dbt_auto.tbl_auto_main_quotes
where disbursal_event_time>'2026/01/31'));

select 1 as ordering, 'People with BP' as metric, count(distinct member_id) as member_count from #people_with_bp
union all
select 2, 'People with BP & Cars', count(distinct member_id) from #people_with_bp_and_cars
union all
select 3, 'People with BP & Cars & Marketing', count(distinct member_id) from #people_with_bp_and_cars_and_marketing
union all
select 4, 'People with BP & Cars & Marketing & Quotes', count(distinct member_id) from #people_with_bp_and_cars_and_marketing_who_are_quoted
union all
select 5,'People with BP & Cars & Marketing & Quotes - Existing Auto', count(distinct member_id) from #people_with_bp_and_cars_and_marketing_who_are_quoted_minus_existing_auto
order by 1;

select * from #people_with_bp_and_cars_and_marketing_who_are_quoted_minus_existing_auto