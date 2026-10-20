-- 風水羅盤 community backend (Supabase). Run once in the SQL Editor.
-- Anyone may read and add plans, comments and ratings; nobody can edit or delete through the website.
-- Remove spam or unwanted entries from the Supabase dashboard (Table Editor / Storage).

create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  building text not null check (char_length(building) between 1 and 120),
  block text check (char_length(block) <= 40),
  floor text check (char_length(floor) <= 40),
  unit text check (char_length(unit) <= 40),
  address text check (char_length(address) <= 300),
  lat double precision check (lat between -90 and 90),
  lng double precision check (lng between -180 and 180),
  facing double precision,
  sector smallint check (sector between 0 and 7),
  label text check (char_length(label) <= 40),
  label_en text check (char_length(label_en) <= 80),
  school text check (school in ('naqi', 'flying', 'mansion')),
  period smallint check (period between 1 and 9),
  author text check (char_length(author) <= 60),
  notes text check (char_length(notes) <= 1000),
  image_path text not null check (char_length(image_path) <= 200),   -- finished picture with compass
  plan_path text check (char_length(plan_path) <= 200),              -- the original floor plan
  layout jsonb,  -- outline, compasses, door, windows, rooms and furniture (no floor-plan image)
  score numeric(2,1) check (score between 1 and 5),  -- overall assessment stars at the time of sharing
  assessment jsonb  -- per item: {"door": {"s": 5, "auto": true}, "beam": {"s": 1, "v": "press"}…}
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  plan_id uuid not null references public.plans(id) on delete cascade,
  author text check (char_length(author) <= 60),
  body text check (char_length(body) <= 2000),
  checks jsonb,          -- structured assessment: 太極點, door, windows, beams, 四象, 動象, 中宮水火…
  overall smallint check (overall between 1 and 5),
  check (body is not null or checks is not null)
);

create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  plan_id uuid not null references public.plans(id) on delete cascade,
  score smallint not null check (score between 1 and 5),
  author text check (char_length(author) <= 60),
  body text check (char_length(body) <= 1000)
);

create index if not exists comments_plan on public.comments(plan_id, created_at);
create index if not exists ratings_plan on public.ratings(plan_id, created_at);

-- average accuracy score and counts per plan, for the gallery
create or replace view public.plan_stats with (security_invoker = true) as
  select p.id,
    (select round(avg(score)::numeric, 1) from public.ratings r where r.plan_id = p.id) as avg_score,
    (select count(*) from public.ratings r where r.plan_id = p.id) as rating_count,
    (select count(*) from public.comments c where c.plan_id = p.id) as comment_count
  from public.plans p;

alter table public.plans enable row level security;
alter table public.comments enable row level security;
alter table public.ratings enable row level security;

drop policy if exists "read plans" on public.plans;
drop policy if exists "add plans" on public.plans;
drop policy if exists "read comments" on public.comments;
drop policy if exists "add comments" on public.comments;
drop policy if exists "read ratings" on public.ratings;
drop policy if exists "add ratings" on public.ratings;
create policy "read plans" on public.plans for select to anon, authenticated using (true);
create policy "add plans" on public.plans for insert to anon, authenticated with check (true);
create policy "read comments" on public.comments for select to anon, authenticated using (true);
create policy "add comments" on public.comments for insert to anon, authenticated with check (true);
create policy "read ratings" on public.ratings for select to anon, authenticated using (true);
create policy "add ratings" on public.ratings for insert to anon, authenticated with check (true);

grant select on public.plan_stats to anon, authenticated;

-- public picture bucket: anyone can view and upload JPEGs up to 3 MB, nobody can overwrite or delete
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('plans', 'plans', true, 3145728, array['image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 3145728, allowed_mime_types = array['image/jpeg'];

drop policy if exists "upload plan pictures" on storage.objects;
create policy "upload plan pictures" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'plans');

-- ---------- Private backup of every case ----------
-- Each upload and each save adds a row; the website can add rows but never read them back.
-- Browse them in the Supabase dashboard (Table Editor → cases, Storage → uploads).
create table if not exists public.cases (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  case_id text not null check (char_length(case_id) <= 40),
  kind text not null check (kind in ('upload', 'save')),
  file_name text check (char_length(file_name) <= 200),
  original_path text check (char_length(original_path) <= 200),
  snapshot_path text check (char_length(snapshot_path) <= 200),
  building text check (char_length(building) <= 120),
  block text check (char_length(block) <= 40),
  floor text check (char_length(floor) <= 40),
  unit text check (char_length(unit) <= 40),
  address text check (char_length(address) <= 300),
  lat double precision, lng double precision,
  facing double precision, label text check (char_length(label) <= 40),
  school text, period smallint, score numeric(2,1),
  layout jsonb
);
create index if not exists cases_case on public.cases(case_id, created_at);
alter table public.cases enable row level security;
drop policy if exists "add cases" on public.cases;
create policy "add cases" on public.cases for insert to anon, authenticated with check (true);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('uploads', 'uploads', false, 15728640, array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif', 'image/bmp'])
on conflict (id) do update set public = false, file_size_limit = 15728640;

drop policy if exists "upload case files" on storage.objects;
create policy "upload case files" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'uploads');
