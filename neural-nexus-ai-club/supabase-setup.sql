-- NEURAL NEXUS shared database setup (Supabase SQL Editor)
-- Run this in a fresh Supabase project. Never put a service-role key in the browser.
create extension if not exists pgcrypto;

create table if not exists public.nn_teams (
  team_id uuid primary key default gen_random_uuid(),
  team_name text not null unique,
  created_at timestamptz not null default now(),
  constraint nn_team_name_length check (char_length(team_name) between 3 and 32),
  constraint nn_team_name_chars check (team_name ~ '^[A-Za-z0-9_-]+$')
);

create table if not exists public.nn_submissions (
  submission_id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.nn_teams(team_id) on delete cascade,
  round_id integer not null check (round_id between 1 and 5),
  question_index integer,
  response_type text not null check (response_type in ('quiz','vision','code','prompt','innovation')),
  answer text,
  content text,
  points integer not null default 0 check (points between 0 and 200),
  submitted_at timestamptz not null default now(),
  judge_status text not null default 'submitted' check (judge_status in ('submitted','reviewed')),
  unique (team_id, round_id, question_index)
);

create table if not exists public.nn_event_state (
  singleton boolean primary key default true check (singleton),
  status text not null default 'waiting' check (status in ('waiting','live','ended')),
  current_round integer not null default 1 check (current_round between 1 and 5),
  updated_at timestamptz not null default now()
);
insert into public.nn_event_state(singleton,status,current_round) values(true,'waiting',1) on conflict(singleton) do nothing;

alter table public.nn_teams enable row level security;
alter table public.nn_submissions enable row level security;
alter table public.nn_event_state enable row level security;
-- The browser gets no direct table permissions. Only narrowly scoped RPC functions below are granted.
revoke all on public.nn_teams from anon, authenticated;
revoke all on public.nn_submissions from anon, authenticated;
revoke all on public.nn_event_state from anon, authenticated;

create or replace function public.nn_join_team(p_team_name text)
returns table(team_id uuid, team_name text)
language plpgsql security definer set search_path = public as $$
declare cleaned text;
begin
  cleaned := regexp_replace(trim(p_team_name), '\s+', '_', 'g');
  if cleaned !~ '^[A-Za-z0-9_-]{3,32}$' then raise exception 'Team name must be 3–32 letters, numbers, underscores, or hyphens'; end if;
  insert into public.nn_teams(team_name) values(cleaned);
  return query select t.team_id,t.team_name from public.nn_teams t where t.team_name=cleaned;
exception when unique_violation then raise exception 'That team name is already taken. Choose another.';
end; $$;

-- Server-side scoring for the built-in sample questions. Correct answers never need to be sent to the browser.
create or replace function public.nn_submit_answer(p_team_id uuid, p_round_id integer, p_question_index integer, p_answer text, p_points integer default 0)
returns table(points_awarded integer, correct boolean)
language plpgsql security definer set search_path = public as $$
declare expected integer; chosen integer; award integer := 0; is_right boolean := false; ev text;
begin
  if not exists(select 1 from public.nn_teams where team_id=p_team_id) then raise exception 'Unknown team'; end if;
  select status into ev from public.nn_event_state where singleton=true;
  if ev <> 'live' then raise exception 'The organizer has not opened the event'; end if;
  if p_round_id not in (1,2) then raise exception 'This round uses written submissions'; end if;
  if p_round_id=1 then
    if p_question_index not between 0 and 4 then raise exception 'Invalid question'; end if;
    expected := case p_question_index when 0 then 1 when 1 then 0 when 2 then 2 when 3 then 1 when 4 then 0 end;
  else
    if p_question_index not between 0 and 2 then raise exception 'Invalid question'; end if;
    expected := case p_question_index when 0 then 0 when 1 then 1 when 2 then 2 end;
  end if;
  begin chosen := p_answer::integer; exception when others then raise exception 'Invalid answer'; end;
  is_right := chosen=expected;
  if is_right then award := 20; end if;
  insert into public.nn_submissions(team_id,round_id,question_index,response_type,answer,points)
  values(p_team_id,p_round_id,p_question_index,case when p_round_id=1 then 'quiz' else 'vision' end,p_answer,award)
  on conflict(team_id,round_id,question_index) do update set answer=excluded.answer,points=excluded.points,submitted_at=now();
  return query select award,is_right;
end; $$;

create or replace function public.nn_submit_open_response(p_team_id uuid, p_round_id integer, p_response_type text, p_content text)
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid; ev text;
begin
  if not exists(select 1 from public.nn_teams where team_id=p_team_id) then raise exception 'Unknown team'; end if;
  if p_round_id not between 3 and 5 then raise exception 'Invalid open-response round'; end if;
  if p_response_type not in ('code','prompt','innovation') then raise exception 'Invalid response type'; end if;
  if length(trim(p_content)) < 15 or length(p_content) > 12000 then raise exception 'Response must be 15–12000 characters'; end if;
  select status into ev from public.nn_event_state where singleton=true;
  if ev <> 'live' then raise exception 'The organizer has not opened the event'; end if;
  insert into public.nn_submissions(team_id,round_id,response_type,content,points)
  values(p_team_id,p_round_id,p_response_type,trim(p_content),0) returning submission_id into new_id;
  return new_id;
end; $$;

create or replace view public.nn_public_leaderboard as
select t.team_id,t.team_name,coalesce(sum(s.points),0)::integer as total_score,
 count(distinct s.round_id)::integer as completed_rounds
from public.nn_teams t left join public.nn_submissions s on s.team_id=t.team_id
group by t.team_id,t.team_name;
-- Only public leaderboard fields are readable. Do not expose response content or answer logs publicly.
grant select on public.nn_public_leaderboard to anon, authenticated;
grant execute on function public.nn_join_team(text) to anon, authenticated;
grant execute on function public.nn_submit_answer(uuid,integer,integer,text,integer) to anon, authenticated;
grant execute on function public.nn_submit_open_response(uuid,integer,text,text) to anon, authenticated;

-- IMPORTANT: event state / admin controls are intentionally not writable by browser clients.
-- For a real event, add a Cloudflare Worker or Supabase Edge Function with server-side admin
-- authentication to start/stop rounds, grade written submissions, export data, and reset scores.

create or replace view public.nn_public_event_state as
select status,current_round,updated_at
from public.nn_event_state where singleton=true;

grant select on public.nn_public_event_state to anon, authenticated;
