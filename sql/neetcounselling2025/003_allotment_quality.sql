alter table neetcounselling2025.allotment_result_effective
  add column if not exists mcc_institute_code int,
  add column if not exists data_quality_flags text[] not null default '{}';

create index if not exists idx_allotment_result_effective_mcc
  on neetcounselling2025.allotment_result_effective(mcc_institute_code);

create index if not exists idx_allotment_result_effective_flags
  on neetcounselling2025.allotment_result_effective using gin(data_quality_flags);

create or replace function neetcounselling2025.sp_refresh_allotment_quality()
returns void
language plpgsql
as $$
begin
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = '{}'
  where data_quality_flags is null;

  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'MISSING_MCC_CODE');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'UNKNOWN_STATE');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'RARE_QUOTA');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'NONCANONICAL_CATEGORY');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'PLACEHOLDER_CATEGORY');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'CANDIDATE_CATEGORY_ANOMALY');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'RECOVERABLE_MCC');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'MCC_CONFLICT');
  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_remove(data_quality_flags, 'QUOTA_VARIANT');

  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = '{}'
  where data_quality_flags = '{NULL}';

  update neetcounselling2025.allotment_result_effective ar
  set mcc_institute_code = i.mcc_institute_code
  from neetcounselling2025.institution i
  where ar.institution_id = i.institution_id
    and ar.mcc_institute_code is null
    and i.mcc_institute_code is not null;

  update neetcounselling2025.allotment_result_effective
  set data_quality_flags = array_append(data_quality_flags, 'MISSING_MCC_CODE')
  where mcc_institute_code is null;

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'UNKNOWN_STATE')
  from neetcounselling2025.institution i
  where ar.institution_id = i.institution_id
    and i.state_name = 'Unknown';

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'RARE_QUOTA')
  from neetcounselling2025.quota q
  where ar.quota_id = q.quota_id
    and q.quota_label in (
      select quota_label from (
        select q2.quota_label, count(*) as cnt
        from neetcounselling2025.allotment_result_effective ar2
        join neetcounselling2025.quota q2 on ar2.quota_id = q2.quota_id
        group by q2.quota_label
        having count(*) < 10
      ) rare
    );

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'NONCANONICAL_CATEGORY')
  from neetcounselling2025.result_category rc
  where ar.allotted_result_category_id = rc.result_category_id
    and rc.normalized_code not in ('OPEN', 'EWS', 'OBC', 'SC', 'ST', '-');

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'PLACEHOLDER_CATEGORY')
  from neetcounselling2025.result_category rc
  where ar.allotted_result_category_id = rc.result_category_id
    and rc.normalized_code = '-';

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'CANDIDATE_CATEGORY_ANOMALY')
  from neetcounselling2025.result_category rc
  where ar.candidate_result_category_id = rc.result_category_id
    and rc.normalized_code not in ('OPEN', 'EWS', 'OBC', 'SC', 'ST', '-');

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'RECOVERABLE_MCC')
  from neetcounselling2025.institution i
  where ar.institution_id = i.institution_id
    and i.mcc_institute_code is null
    and exists (
      select 1 from neetcounselling2025.institution_alias ia
      where ia.institution_id = i.institution_id
        and ia.alias_raw ~ '\(\d{6}\)'
    );

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'MCC_CONFLICT')
  from neetcounselling2025.institution i
  where ar.institution_id = i.institution_id
    and exists (
      select 1 from neetcounselling2025.institution_alias ia1
      join neetcounselling2025.institution_alias ia2 on ia1.institution_id = ia2.institution_id
      where ia1.institution_id = i.institution_id
        and ia1.alias_raw ~ '\(\d{6}\)'
        and ia2.alias_raw ~ '\(\d{6}\)'
        and (regexp_match(ia1.alias_raw, '\((\d{6})\)'))[1] <> (regexp_match(ia2.alias_raw, '\((\d{6})\)'))[1]
    );

  update neetcounselling2025.allotment_result_effective ar
  set data_quality_flags = array_append(ar.data_quality_flags, 'QUOTA_VARIANT')
  from neetcounselling2025.quota q
  where ar.quota_id = q.quota_id
    and exists (
      select 1 from neetcounselling2025.quota q2
      where q2.quota_id <> q.quota_id
        and regexp_replace(lower(regexp_replace(q.quota_label, '[^a-zA-Z0-9]', '', 'g')), '\s+', '') =
            regexp_replace(lower(regexp_replace(q2.quota_label, '[^a-zA-Z0-9]', '', 'g')), '\s+', '')
    );
end;
$$;

create unique index if not exists idx_institution_mcc_unique
  on neetcounselling2025.institution(mcc_institute_code)
  where mcc_institute_code is not null;
