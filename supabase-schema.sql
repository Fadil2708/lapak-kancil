create extension if not exists pgcrypto with schema extensions;

create table if not exists public.lapak_classes (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  invite_code text not null unique default encode(extensions.gen_random_bytes(12), 'hex'),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.lapak_students (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.lapak_classes(id) on delete cascade,
  nickname text not null check (char_length(btrim(nickname)) between 1 and 12),
  session_token_hash text not null unique,
  progress jsonb not null default '{}'::jsonb check (jsonb_typeof(progress) = 'object'),
  reset_version integer not null default 0 check (reset_version >= 0),
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

alter table public.lapak_students
  add column if not exists reset_version integer not null default 0;

create table if not exists public.lapak_reset_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.lapak_students(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'denied')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);

create index if not exists lapak_reset_requests_student_id_idx on public.lapak_reset_requests(student_id);
create unique index if not exists lapak_reset_requests_one_pending_per_student_idx
  on public.lapak_reset_requests(student_id) where status = 'pending';
create index if not exists lapak_classes_teacher_id_idx on public.lapak_classes(teacher_id);
create index if not exists lapak_students_class_id_idx on public.lapak_students(class_id);

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'lapak_reset_requests'
    ) then
    alter publication supabase_realtime add table public.lapak_reset_requests;
  end if;
end;
$$;

alter table public.lapak_classes enable row level security;
alter table public.lapak_students enable row level security;
alter table public.lapak_reset_requests enable row level security;

drop policy if exists "Teachers manage their classes" on public.lapak_classes;
create policy "Teachers manage their classes"
  on public.lapak_classes
  for all
  to authenticated
  using (teacher_id = (select auth.uid()))
  with check (teacher_id = (select auth.uid()));

drop policy if exists "Teachers view students in their classes" on public.lapak_students;
create policy "Teachers view students in their classes"
  on public.lapak_students
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.lapak_classes
      where lapak_classes.id = lapak_students.class_id
        and lapak_classes.teacher_id = (select auth.uid())
    )
  );

drop policy if exists "Teachers remove students from their classes" on public.lapak_students;
create policy "Teachers remove students from their classes"
  on public.lapak_students
  for delete
  to authenticated
  using (
    exists (
      select 1
      from public.lapak_classes
      where lapak_classes.id = lapak_students.class_id
        and lapak_classes.teacher_id = (select auth.uid())
    )
  );

drop policy if exists "Teachers view reset requests in their classes" on public.lapak_reset_requests;
create policy "Teachers view reset requests in their classes"
  on public.lapak_reset_requests
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.lapak_students
      join public.lapak_classes on lapak_classes.id = lapak_students.class_id
      where lapak_students.id = lapak_reset_requests.student_id
        and lapak_classes.teacher_id = (select auth.uid())
    )
  );

revoke all on public.lapak_classes, public.lapak_students, public.lapak_reset_requests from public, anon, authenticated;
grant select, insert, update, delete on public.lapak_classes to authenticated;
grant select, delete on public.lapak_students to authenticated;
grant select on public.lapak_reset_requests to authenticated;

create or replace function public.lapak_broadcast_reset_decision()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status is distinct from new.status and new.status in ('approved', 'denied') then
    perform realtime.send(
      payload => jsonb_build_object('request_id', new.id, 'status', new.status),
      event => 'reset_decision',
      topic => 'lapak-reset-' || new.id::text,
      private => false
    );
  end if;
  return new;
end;
$$;

revoke all on function public.lapak_broadcast_reset_decision() from public, anon, authenticated;
drop trigger if exists lapak_reset_decision_broadcast on public.lapak_reset_requests;
create trigger lapak_reset_decision_broadcast
  after update of status on public.lapak_reset_requests
  for each row
  execute function public.lapak_broadcast_reset_decision();

drop function if exists public.lapak_student_save_progress(uuid, text, jsonb);
drop function if exists public.lapak_student_save_progress(uuid, text, text, jsonb);

create or replace function public.lapak_student_join_class(
  p_invite_code text,
  p_nickname text,
  p_session_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_class_id uuid;
  v_class_name text;
  v_student_id uuid;
  v_existing_class_id uuid;
  v_nickname text := btrim(p_nickname);
  v_token_hash text;
begin
  if p_session_token is null or p_session_token !~ '^[a-f0-9]{64}$' then
    raise exception 'ID perangkat tidak valid.';
  end if;
  if v_nickname is null
    or char_length(v_nickname) not between 1 and 12
    or v_nickname ~ '[[:cntrl:]]' then
    raise exception 'Nama panggilan harus 1 sampai 12 karakter.';
  end if;

  select c.id, c.name
    into v_class_id, v_class_name
    from public.lapak_classes as c
    where c.invite_code = lower(btrim(p_invite_code))
      and c.is_active = true;
  if v_class_id is null then
    raise exception 'Tautan kelas tidak ditemukan atau sudah dinonaktifkan.';
  end if;

  v_token_hash := encode(extensions.digest(p_session_token, 'sha256'), 'hex');
  select s.id, s.class_id
    into v_student_id, v_existing_class_id
    from public.lapak_students as s
    where s.session_token_hash = v_token_hash;

  if v_student_id is not null then
    if v_existing_class_id <> v_class_id then
      raise exception 'ID murid ini sudah terhubung ke kelas lain di perangkat ini.';
    end if;
    update public.lapak_students
      set nickname = v_nickname, updated_at = now(), last_seen_at = now()
      where id = v_student_id;
  else
    insert into public.lapak_students (class_id, nickname, session_token_hash)
      values (v_class_id, v_nickname, v_token_hash)
      returning id into v_student_id;
  end if;

  return jsonb_build_object(
    'student_id', v_student_id,
    'class_name', v_class_name,
    'reset_version', (select s.reset_version from public.lapak_students as s where s.id = v_student_id),
    'reset_request_id', (
      select r.id
      from public.lapak_reset_requests as r
      where r.student_id = v_student_id and r.status = 'pending'
      order by r.requested_at desc
      limit 1
    ),
    'reset_status', (
      select r.status
      from public.lapak_reset_requests as r
      where r.student_id = v_student_id
      order by r.requested_at desc
      limit 1
    )
  );
end;
$$;

create or replace function public.lapak_student_sync_progress(
  p_student_id uuid,
  p_session_token text,
  p_nickname text,
  p_progress jsonb,
  p_reset_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token_hash text;
  v_nickname text := btrim(p_nickname);
  v_reset_version integer;
  v_reset_status text;
  v_reset_request_id uuid;
begin
  if p_session_token is null
    or p_session_token !~ '^[a-f0-9]{64}$'
    or v_nickname is null
    or char_length(v_nickname) not between 1 and 12
    or v_nickname ~ '[[:cntrl:]]'
    or p_progress is null
    or jsonb_typeof(p_progress) <> 'object'
    or p_reset_version is null
    or p_reset_version < 0
    or octet_length(p_progress::text) > 12000 then
    raise exception 'Data progres tidak valid.';
  end if;

  v_token_hash := encode(extensions.digest(p_session_token, 'sha256'), 'hex');
  select s.reset_version
    into v_reset_version
    from public.lapak_students as s
    where s.id = p_student_id
      and s.session_token_hash = v_token_hash
    for update;
  if not found then
    raise exception 'Sesi murid tidak dikenali. Buka kembali tautan kelas.';
  end if;

  select r.id, r.status
    into v_reset_request_id, v_reset_status
    from public.lapak_reset_requests as r
    where r.student_id = p_student_id
    order by r.requested_at desc
    limit 1;

  if v_reset_version <> p_reset_version then
    return jsonb_build_object(
      'reset_required', true,
      'reset_version', v_reset_version,
      'reset_status', v_reset_status,
      'reset_request_id', v_reset_request_id
    );
  end if;

  update public.lapak_students
    set nickname = v_nickname, progress = p_progress, updated_at = now(), last_seen_at = now()
    where id = p_student_id
      and session_token_hash = v_token_hash;
  return jsonb_build_object(
    'reset_required', false,
    'reset_version', v_reset_version,
    'reset_status', v_reset_status,
    'reset_request_id', v_reset_request_id
  );
end;
$$;

create or replace function public.lapak_student_request_reset(
  p_student_id uuid,
  p_session_token text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token_hash text;
  v_request_id uuid;
begin
  if p_session_token is null or p_session_token !~ '^[a-f0-9]{64}$' then
    raise exception 'Sesi murid tidak valid.';
  end if;
  v_token_hash := encode(extensions.digest(p_session_token, 'sha256'), 'hex');
  if not exists (
    select 1
    from public.lapak_students as s
    where s.id = p_student_id and s.session_token_hash = v_token_hash
  ) then
    raise exception 'Sesi murid tidak dikenali.';
  end if;

  select r.id into v_request_id
    from public.lapak_reset_requests as r
    where r.student_id = p_student_id and r.status = 'pending'
    order by r.requested_at desc
    limit 1;
  if v_request_id is null then
    insert into public.lapak_reset_requests (student_id)
      values (p_student_id)
      on conflict (student_id) where status = 'pending' do nothing
      returning id into v_request_id;
    if v_request_id is null then
      select r.id into v_request_id
        from public.lapak_reset_requests as r
        where r.student_id = p_student_id and r.status = 'pending'
        order by r.requested_at desc
        limit 1;
    end if;
  end if;
  return jsonb_build_object('request_id', v_request_id, 'status', 'pending');
end;
$$;

create or replace function public.lapak_teacher_review_reset(
  p_request_id uuid,
  p_approve boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_student_id uuid;
  v_status text;
begin
  if auth.uid() is null or p_approve is null then
    raise exception 'Guru harus masuk untuk meninjau permintaan.';
  end if;
  select r.student_id, r.status
    into v_student_id, v_status
    from public.lapak_reset_requests as r
    join public.lapak_students as s on s.id = r.student_id
    join public.lapak_classes as c on c.id = s.class_id
    where r.id = p_request_id and c.teacher_id = auth.uid()
    for update of r, s;
  if v_student_id is null then
    raise exception 'Permintaan tidak ditemukan atau bukan milik kelasmu.';
  end if;
  if v_status <> 'pending' then
    raise exception 'Permintaan ini sudah ditinjau.';
  end if;

  if p_approve then
    update public.lapak_students
      set progress = '{}'::jsonb, reset_version = reset_version + 1, updated_at = now()
      where id = v_student_id;
  end if;
  update public.lapak_reset_requests
    set status = case when p_approve then 'approved' else 'denied' end,
        reviewed_at = now(),
        reviewed_by = auth.uid()
    where id = p_request_id;
  return true;
end;
$$;

revoke all on function public.lapak_student_join_class(text, text, text) from public;
revoke all on function public.lapak_student_sync_progress(uuid, text, text, jsonb, integer) from public;
revoke all on function public.lapak_student_request_reset(uuid, text) from public;
revoke all on function public.lapak_teacher_review_reset(uuid, boolean) from public;
grant execute on function public.lapak_student_join_class(text, text, text) to anon, authenticated;
grant execute on function public.lapak_student_sync_progress(uuid, text, text, jsonb, integer) to anon, authenticated;
grant execute on function public.lapak_student_request_reset(uuid, text) to anon, authenticated;
grant execute on function public.lapak_teacher_review_reset(uuid, boolean) to authenticated;
