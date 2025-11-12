-- Admin referral diagnostics and backfill functions
create or replace function public.admin_referral_diagnose()
returns table (user_id uuid, email text, issue text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.has_role(auth.uid(), 'admin') or public.has_role(auth.uid(), 'superadmin')) then
    raise exception 'UNAUTHORIZED';
  end if;

  return query
  -- Users without sponsor_id and without referral row
  select p.id, p.email, 'no_sponsor_and_no_referral'::text as issue
  from public.profiles p
  left join public.referrals r on r.referred_user_id = p.id
  where p.deleted_at is null
    and (p.is_archived is null or p.is_archived = false)
    and p.is_active = true
    and p.sponsor_id is null
    and r.id is null
  union all
  -- Users with sponsor_id but missing referral row
  select p.id, p.email, 'missing_referral_row'::text as issue
  from public.profiles p
  where p.sponsor_id is not null
    and not exists (select 1 from public.referrals r where r.referred_user_id = p.id);
end;
$$;

grant execute on function public.admin_referral_diagnose() to authenticated;

create or replace function public.admin_referral_backfill()
returns table(updated_sponsor_ids integer, inserted_referrals integer, recalculated_direct_counts integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int := 0;
  v_inserted int := 0;
  v_recalc int := 0;
begin
  if not (public.has_role(auth.uid(), 'admin') or public.has_role(auth.uid(), 'superadmin')) then
    raise exception 'UNAUTHORIZED';
  end if;

  -- 1) Fill sponsor_id from existing referrals
  update public.profiles p
  set sponsor_id = r.referrer_id
  from public.referrals r
  where p.id = r.referred_user_id
    and p.sponsor_id is null;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  -- 2) Ensure referral rows exist for all profiles with sponsor_id
  insert into public.referrals (referrer_id, referred_user_id, structure_type, utm_source, utm_campaign, utm_medium)
  select p.sponsor_id, p.id, 1,
         coalesce(p.referrer_snapshot->>'utm_source', null),
         coalesce(p.referrer_snapshot->>'utm_campaign', null),
         coalesce(p.referrer_snapshot->>'utm_medium', null)
  from public.profiles p
  where p.sponsor_id is not null
    and not exists (select 1 from public.referrals r where r.referred_user_id = p.id);
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  -- 3) Recalculate direct_referrals_count on sponsors
  update public.profiles s
  set direct_referrals_count = coalesce(sub.cnt, 0)
  from (
    select r.referrer_id as id, count(*)::int as cnt
    from public.referrals r
    group by r.referrer_id
  ) sub
  where s.id = sub.id;
  GET DIAGNOSTICS v_recalc = ROW_COUNT;

  return query select v_updated, v_inserted, v_recalc;
end;
$$;

grant execute on function public.admin_referral_backfill() to authenticated;