-- Board @ ASYS — Supabase şeması (v1, 03.11.2026)
-- Tarayıcı anon (publishable) anahtarla sadece OKUR; tüm yazmalar aşağıdaki
-- board_* fonksiyonları üzerinden, oturum token'ı ile yapılır.

create extension if not exists pgcrypto;

-- ---------- tablolar ----------
create table if not exists people (
  id          text primary key,
  name        text not null,
  role        text not null default '',
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists pins (                -- anon erişimi YOK
  person_id   text primary key references people(id) on delete cascade,
  pin_hash    text not null
);

create table if not exists secrets (             -- anon erişimi YOK
  key         text primary key,
  value       text not null
);

create table if not exists settings (            -- herkes okur (pm şifresi burada DEĞİL)
  key         text primary key,
  value       jsonb not null default '{}'::jsonb
);

create table if not exists items (
  id          text primary key,
  no          integer not null,
  title       text not null,
  descr       text not null default '',
  priority    text not null default 'normal',
  status      text not null default 'acik',
  by_person   text not null default '',
  by_name     text not null default '',
  at          timestamptz not null default now(),
  assignee    text not null default '',
  due         text not null default '',
  decision    text not null default '',
  meeting     text not null default '',
  closed_at   text not null default '',
  done_at     text not null default '',
  done_by     text not null default '',
  comments    jsonb not null default '[]'::jsonb,
  updated_at  timestamptz not null default now()
);
create unique index if not exists items_no_idx on items(no);

create table if not exists sessions (            -- anon erişimi YOK
  token       text primary key,
  person_id   text not null references people(id) on delete cascade,
  role        text not null default 'site',      -- site | pm
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '180 days'
);

-- ---------- RLS ----------
alter table people   enable row level security;
alter table pins     enable row level security;
alter table secrets  enable row level security;
alter table settings enable row level security;
alter table items    enable row level security;
alter table sessions enable row level security;

drop policy if exists people_read   on people;
drop policy if exists settings_read on settings;
drop policy if exists items_read    on items;
create policy people_read   on people   for select to anon, authenticated using (true);
create policy settings_read on settings for select to anon, authenticated using (true);
create policy items_read    on items    for select to anon, authenticated using (true);
-- pins / secrets / sessions: hiç policy yok → anon göremez. Yazma: hiçbir tabloda policy yok → sadece fonksiyonlar.

grant usage on schema public to anon, authenticated;
grant select on people, settings, items to anon, authenticated;

-- ---------- yardımcılar ----------
create or replace function board_session(p_token text)
returns sessions language sql security definer stable as $$
  select * from sessions where token = p_token and expires_at > now();
$$;

create or replace function board_require(p_token text, p_pm boolean default false)
returns sessions language plpgsql security definer as $$
declare s sessions;
begin
  select * into s from sessions where token = p_token and expires_at > now();
  if s.token is null then raise exception 'not_logged_in'; end if;
  if p_pm and s.role <> 'pm' then raise exception 'pm_required'; end if;
  return s;
end $$;

-- ---------- giriş ----------
create or replace function board_login(p_person text, p_pin text)
returns jsonb language plpgsql security definer as $$
declare h text; tok text; p people;
begin
  select * into p from people where id = p_person and active;
  if p.id is null then raise exception 'no_person'; end if;
  select pin_hash into h from pins where person_id = p_person;
  if h is null or h <> crypt(p_pin, h) then raise exception 'bad_pin'; end if;
  tok := encode(gen_random_bytes(24), 'hex');
  insert into sessions(token, person_id) values (tok, p_person);
  return jsonb_build_object('token', tok, 'person', p_person, 'role', 'site');
end $$;

create or replace function board_pm_login(p_token text, p_pass text)
returns jsonb language plpgsql security definer as $$
declare s sessions; h text;
begin
  s := board_require(p_token);
  select value into h from secrets where key = 'pm_hash';
  if h is null or h <> crypt(p_pass, h) then raise exception 'bad_pass'; end if;
  update sessions set role = 'pm' where token = p_token;
  return jsonb_build_object('person', s.person_id, 'role', 'pm');
end $$;

create or replace function board_pm_logout(p_token text)
returns void language sql security definer as $$
  update sessions set role = 'site' where token = p_token;
$$;

create or replace function board_logout(p_token text)
returns void language sql security definer as $$
  delete from sessions where token = p_token;
$$;

create or replace function board_me(p_token text)
returns jsonb language plpgsql security definer stable as $$
declare s sessions;
begin
  select * into s from sessions where token = p_token and expires_at > now();
  if s.token is null then return null; end if;
  return jsonb_build_object('person', s.person_id, 'role', s.role);
end $$;

-- ---------- maddeler ----------
create or replace function board_create_item(p_token text, p_title text, p_descr text)
returns items language plpgsql security definer as $$
declare s sessions; n int; r items; nm text;
begin
  s := board_require(p_token);
  if length(trim(p_title)) = 0 then raise exception 'title_required'; end if;
  select coalesce(max(no),0)+1 into n from items;
  select name into nm from people where id = s.person_id;
  insert into items(id, no, title, descr, by_person, by_name)
    values (encode(gen_random_bytes(8),'hex'), n, trim(p_title), coalesce(p_descr,''), s.person_id, coalesce(nm,''))
    returning * into r;
  return r;
end $$;

-- p_patch: panelin item nesnesi (camelCase anahtarlar). PM her şeyi değiştirir;
-- saha kullanıcısı: kendi açtığı 'acik' maddede title/descr; atanan/açan kişi status→yapildi / geri alma.
create or replace function board_update_item(p_token text, p_id text, p_patch jsonb)
returns items language plpgsql security definer as $$
declare s sessions; cur items; r items; ns text;
begin
  s := board_require(p_token);
  select * into cur from items where id = p_id;
  if cur.id is null then raise exception 'no_item'; end if;
  if s.role = 'pm' then
    update items set
      title     = coalesce(p_patch->>'title', title),
      descr     = coalesce(p_patch->>'desc', descr),
      priority  = coalesce(p_patch->>'priority', priority),
      status    = coalesce(p_patch->>'status', status),
      assignee  = coalesce(p_patch->>'assignee', assignee),
      due       = coalesce(p_patch->>'due', due),
      decision  = coalesce(p_patch->>'decision', decision),
      meeting   = coalesce(p_patch->>'meeting', meeting),
      closed_at = coalesce(p_patch->>'closedAt', closed_at),
      done_at   = coalesce(p_patch->>'doneAt', done_at),
      done_by   = coalesce(p_patch->>'doneBy', done_by),
      updated_at = now()
    where id = p_id returning * into r;
    return r;
  end if;
  -- saha kullanıcısı
  ns := p_patch->>'status';
  if ns is not null and ns <> cur.status then
    if not (cur.assignee = s.person_id or cur.by_person = s.person_id) then raise exception 'not_allowed'; end if;
    if ns = 'yapildi' and cur.status in ('acik','gorusuldu','cozumde') then
      update items set status='yapildi', done_at=now()::text, done_by=s.person_id, updated_at=now() where id=p_id returning * into r;
      return r;
    elsif cur.status = 'yapildi' and ns in ('acik','gorusuldu') then
      update items set status=ns, done_at='', done_by='', updated_at=now() where id=p_id returning * into r;
      return r;
    else
      raise exception 'not_allowed';
    end if;
  end if;
  if (p_patch ? 'title' or p_patch ? 'desc') then
    if not (cur.by_person = s.person_id and cur.status = 'acik') then raise exception 'not_allowed'; end if;
    update items set title=coalesce(p_patch->>'title',title), descr=coalesce(p_patch->>'desc',descr), updated_at=now() where id=p_id returning * into r;
    return r;
  end if;
  return cur;
end $$;

create or replace function board_add_comment(p_token text, p_id text, p_text text)
returns items language plpgsql security definer as $$
declare s sessions; r items; nm text;
begin
  s := board_require(p_token);
  if length(trim(p_text)) = 0 then raise exception 'empty'; end if;
  select name into nm from people where id = s.person_id;
  update items set comments = comments || jsonb_build_array(jsonb_build_object('by', s.person_id, 'byName', coalesce(nm,''), 'at', now(), 'text', trim(p_text))), updated_at = now()
    where id = p_id returning * into r;
  if r.id is null then raise exception 'no_item'; end if;
  return r;
end $$;

create or replace function board_delete_item(p_token text, p_id text)
returns void language plpgsql security definer as $$
declare s sessions;
begin
  s := board_require(p_token, true);
  delete from items where id = p_id;
end $$;

-- ---------- ekip / ayarlar (PM) ----------
create or replace function board_upsert_person(p_token text, p_id text, p_name text, p_role text, p_active boolean, p_pin text)
returns people language plpgsql security definer as $$
declare s sessions; r people; pid text;
begin
  s := board_require(p_token, true);
  pid := coalesce(nullif(p_id,''), 'p' || encode(gen_random_bytes(5),'hex'));
  insert into people(id, name, role, active) values (pid, trim(p_name), coalesce(p_role,''), coalesce(p_active,true))
    on conflict (id) do update set name = excluded.name, role = excluded.role, active = excluded.active
    returning * into r;
  if p_pin is not null and length(p_pin) >= 4 then
    insert into pins(person_id, pin_hash) values (pid, crypt(p_pin, gen_salt('bf')))
      on conflict (person_id) do update set pin_hash = excluded.pin_hash;
  end if;
  return r;
end $$;

create or replace function board_set_pm_password(p_token text, p_pass text)
returns void language plpgsql security definer as $$
declare s sessions;
begin
  s := board_require(p_token, true);
  if length(p_pass) < 4 then raise exception 'too_short'; end if;
  insert into secrets(key, value) values ('pm_hash', crypt(p_pass, gen_salt('bf')))
    on conflict (key) do update set value = excluded.value;
end $$;

create or replace function board_set_setting(p_token text, p_key text, p_value jsonb)
returns void language plpgsql security definer as $$
declare s sessions;
begin
  s := board_require(p_token, true);
  insert into settings(key, value) values (p_key, p_value) on conflict (key) do update set value = excluded.value;
end $$;

-- fonksiyonları anon çağırabilsin
grant execute on function
  board_login(text,text), board_pm_login(text,text), board_pm_logout(text), board_logout(text), board_me(text),
  board_create_item(text,text,text), board_update_item(text,text,jsonb), board_add_comment(text,text,text), board_delete_item(text,text),
  board_upsert_person(text,text,text,text,boolean,text), board_set_pm_password(text,text), board_set_setting(text,text,jsonb)
  to anon, authenticated;
revoke execute on function board_session(text), board_require(text,boolean) from anon, authenticated, public;

-- ---------- realtime ----------
do $$ begin
  alter publication supabase_realtime add table items;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table people;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table settings;
exception when duplicate_object then null; end $$;

-- ---------- başlangıç verisi ----------
-- İlk kurulumda PM, SQL Editor'dan kendi kullanıcısını ve PM şifresini oluşturur:
--   insert into people(id,name,role) values ('p-xxx','Ad Soyad','Görev');
--   insert into pins(person_id,pin_hash) values ('p-xxx', crypt('<PIN>', gen_salt('bf')));
--   insert into secrets(key,value) values ('pm_hash', crypt('<PM şifresi>', gen_salt('bf')));
--   insert into settings(key,value) values ('site','{"project":"Wildberries Almaty"}');
