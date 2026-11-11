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
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists lapak_classes_teacher_id_idx on public.lapak_classes(teacher_id);
create index if not exists lapak_students_class_id_idx on public.lapak_students(class_id);

alter table public.lapak_classes enable row level security;
alter table public.lapak_students enable row level security;

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

revoke all on public.lapak_classes, public.lapak_students from public, anon, authenticated;
grant select, insert, update, delete on public.lapak_classes to authenticated;
grant select, delete on public.lapak_students to authenticated;

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

  return jsonb_build_object('student_id', v_student_id, 'class_name', v_class_name);
end;
$$;

create or replace function public.lapak_student_save_progress(
  p_student_id uuid,
  p_session_token text,
  p_nickname text,
  p_progress jsonb
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_token_hash text;
  v_nickname text := btrim(p_nickname);
begin
  if p_session_token is null
    or p_session_token !~ '^[a-f0-9]{64}$'
    or v_nickname is null
    or char_length(v_nickname) not between 1 and 12
    or v_nickname ~ '[[:cntrl:]]'
    or p_progress is null
    or jsonb_typeof(p_progress) <> 'object'
    or octet_length(p_progress::text) > 12000 then
    raise exception 'Data progres tidak valid.';
  end if;

  v_token_hash := encode(extensions.digest(p_session_token, 'sha256'), 'hex');
  update public.lapak_students
    set nickname = v_nickname, progress = p_progress, updated_at = now(), last_seen_at = now()
    where id = p_student_id
      and session_token_hash = v_token_hash;
  if not found then
    raise exception 'Sesi murid tidak dikenali. Buka kembali tautan kelas.';
  end if;
  return true;
end;
$$;

revoke all on function public.lapak_student_join_class(text, text, text) from public;
revoke all on function public.lapak_student_save_progress(uuid, text, text, jsonb) from public;
grant execute on function public.lapak_student_join_class(text, text, text) to anon, authenticated;
grant execute on function public.lapak_student_save_progress(uuid, text, text, jsonb) to anon, authenticated;
