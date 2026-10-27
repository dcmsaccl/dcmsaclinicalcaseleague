-- Follow check: run once, after setup.sql (or after update-existing.sql)
create table if not exists follow_checks (
  instagram text primary key check (instagram ~ '^[a-z0-9._]{1,30}$'),
  status text not null check (status in ('verified','disqualified')),
  updated_at timestamptz default now()
);
alter table follow_checks enable row level security;
create policy "anyone reads follow checks" on follow_checks for select using (true);
create policy "faculty write follow checks" on follow_checks for all to authenticated using (true) with check (true);

create or replace function check_limits() returns trigger language plpgsql as $$
declare n int; lim int;
begin
  new.instagram := lower(regexp_replace(coalesce(new.instagram,''),'^@',''));
  if new.instagram = '' then raise exception 'Instagram username is required'; end if;
  if exists (select 1 from follow_checks where instagram = new.instagram and status = 'disqualified') then
    raise exception 'This account has been disqualified'; end if;
  lim := case new.category when 'Operative' then 2 else 1 end;
  select count(*) into n from submissions
    where instagram = new.instagram and category = new.category
      and date_trunc('week', created_at) = date_trunc('week', now());
  if n >= lim then raise exception 'Weekly limit reached for % (max % per week)', new.category, lim; end if;
  return new;
end $$;
