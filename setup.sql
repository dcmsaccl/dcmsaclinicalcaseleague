-- FRESH SETUP. Run once in Supabase: SQL Editor > New query > paste > Run
create table submissions (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  instagram text check (instagram ~ '^[a-z0-9._]{1,30}$'),
  level text not null,
  category text not null check (category in ('Operative','Endo','Fixed')),
  note text check (char_length(note) <= 400),
  photo_urls text[] not null check (array_length(photo_urls,1) between 1 and 6),
  rank int check (rank between 1 and 5),
  created_at timestamptz default now()
);
alter table submissions enable row level security;
create policy "anyone reads"   on submissions for select using (true);
create policy "anyone submits" on submissions for insert with check (rank is null);
create policy "faculty rank"   on submissions for update to authenticated using (true) with check (true);
create policy "faculty delete" on submissions for delete to authenticated using (true);

insert into storage.buckets (id, name, public) values ('case-photos','case-photos',true);
create policy "anyone uploads photos" on storage.objects for insert with check (bucket_id = 'case-photos');
create policy "anyone views photos"   on storage.objects for select using (bucket_id = 'case-photos');

-- Weekly limits: 2 Operative, 1 Endo, 1 Fixed per Instagram username
create or replace function check_limits() returns trigger language plpgsql as $$
declare n int; lim int;
begin
  new.instagram := lower(regexp_replace(coalesce(new.instagram,''),'^@',''));
  if new.instagram = '' then raise exception 'Instagram username is required'; end if;
  lim := case new.category when 'Operative' then 2 else 1 end;
  select count(*) into n from submissions
    where instagram = new.instagram and category = new.category
      and date_trunc('week', created_at) = date_trunc('week', now());
  if n >= lim then raise exception 'Weekly limit reached for % (max % per week)', new.category, lim; end if;
  return new;
end $$;
create trigger limits before insert on submissions for each row execute function check_limits();

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
