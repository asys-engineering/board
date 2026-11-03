-- 004: fotoğraflar (veritabanında, oturum korumalı). 03.11.2026
alter table items add column if not exists photos jsonb not null default '[]'::jsonb;

create table if not exists photos (
  id        text primary key,
  item_id   text not null references items(id) on delete cascade,
  data      bytea not null,
  mime      text not null default 'image/jpeg',
  by_person text not null default '',
  at        timestamptz not null default now()
);
alter table photos enable row level security;

-- ekle: base64 JPEG, en çok 1,5 MB
create or replace function board_add_photo(p_token text, p_item text, p_b64 text)
returns text language plpgsql security definer as $$
declare s sessions; pid text; raw bytea;
begin
  s := board_require(p_token);
  if not exists (select 1 from items where id = p_item) then raise exception 'no_item'; end if;
  raw := decode(p_b64, 'base64');
  if length(raw) > 1572864 then raise exception 'too_large'; end if;
  pid := encode(gen_random_bytes(8), 'hex');
  insert into photos(id, item_id, data, by_person) values (pid, p_item, raw, s.person_id);
  update items set photos = photos || to_jsonb(pid), updated_at = now() where id = p_item;
  return pid;
end $$;

-- oku: base64
create or replace function board_photo(p_token text, p_id text)
returns text language plpgsql security definer stable as $$
declare s sessions; d bytea;
begin
  s := board_require(p_token);
  select data into d from photos where id = p_id;
  if d is null then raise exception 'no_photo'; end if;
  return encode(d, 'base64');
end $$;

-- sil: yönetici veya yükleyen
create or replace function board_delete_photo(p_token text, p_id text)
returns void language plpgsql security definer as $$
declare s sessions; ph photos;
begin
  s := board_require(p_token);
  select * into ph from photos where id = p_id;
  if ph.id is null then return; end if;
  if s.role <> 'pm' and ph.by_person <> s.person_id then raise exception 'not_allowed'; end if;
  delete from photos where id = p_id;
  update items set photos = (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(photos) x where x <> to_jsonb(p_id)), updated_at = now() where id = ph.item_id;
end $$;

grant execute on function board_add_photo(text,text,text), board_photo(text,text), board_delete_photo(text,text) to anon, authenticated;
