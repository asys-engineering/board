-- 002: e-posta + şifre girişi (PIN yerine). 03.11.2026
alter table people add column if not exists email text;
create unique index if not exists people_email_idx on people (lower(email));

-- giriş: e-posta + şifre
drop function if exists board_login(text, text) cascade;
create or replace function board_login(p_email text, p_password text)
returns jsonb language plpgsql security definer as $$
declare h text; tok text; p people;
begin
  select * into p from people where lower(email) = lower(trim(p_email)) and active;
  if p.id is null then raise exception 'bad_login'; end if;
  select pin_hash into h from pins where person_id = p.id;
  if h is null or h <> crypt(p_password, h) then raise exception 'bad_login'; end if;
  tok := encode(gen_random_bytes(24), 'hex');
  insert into sessions(token, person_id) values (tok, p.id);
  return jsonb_build_object('token', tok, 'person', p.id, 'role', 'site');
end $$;

-- kişi ekle/güncelle: e-posta alanı eklendi; p_pin = geçici şifre (>= 6)
drop function if exists board_upsert_person(text, text, text, text, boolean, text);
create or replace function board_upsert_person(p_token text, p_id text, p_name text, p_role text, p_email text, p_active boolean, p_pin text)
returns people language plpgsql security definer as $$
declare s sessions; r people; pid text;
begin
  s := board_require(p_token, true);
  pid := coalesce(nullif(p_id,''), 'p' || encode(gen_random_bytes(5),'hex'));
  if p_email is null or position('@' in p_email) = 0 then raise exception 'bad_email'; end if;
  insert into people(id, name, role, email, active) values (pid, trim(p_name), coalesce(p_role,''), lower(trim(p_email)), coalesce(p_active,true))
    on conflict (id) do update set name = excluded.name, role = excluded.role, email = excluded.email, active = excluded.active
    returning * into r;
  if p_pin is not null and length(p_pin) >= 6 then
    insert into pins(person_id, pin_hash) values (pid, crypt(p_pin, gen_salt('bf')))
      on conflict (person_id) do update set pin_hash = excluded.pin_hash;
  end if;
  return r;
end $$;

-- kullanıcı kendi şifresini değiştirir
create or replace function board_change_password(p_token text, p_old text, p_new text)
returns void language plpgsql security definer as $$
declare s sessions; h text;
begin
  s := board_require(p_token);
  if length(p_new) < 6 then raise exception 'too_short'; end if;
  select pin_hash into h from pins where person_id = s.person_id;
  if h is null or h <> crypt(p_old, h) then raise exception 'bad_old'; end if;
  update pins set pin_hash = crypt(p_new, gen_salt('bf')) where person_id = s.person_id;
end $$;

grant execute on function board_login(text,text), board_upsert_person(text,text,text,text,text,boolean,text), board_change_password(text,text,text) to anon, authenticated;

-- mevcut kullanıcı
update people set email = 'huseyin.ozkan@asys-engineering.com' where id = 'p-huseyin' and email is null;
