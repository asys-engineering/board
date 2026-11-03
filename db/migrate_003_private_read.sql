-- 003: Okuma da oturum gerektirir. Anonim okuma politikaları kaldırılır; veri board_fetch(token) ile alınır. 03.11.2026
drop policy if exists people_read   on people;
drop policy if exists settings_read on settings;
drop policy if exists items_read    on items;
revoke select on people, settings, items from anon, authenticated;

create or replace function board_fetch(p_token text)
returns jsonb language plpgsql security definer stable as $$
declare s sessions;
begin
  select * into s from sessions where token = p_token and expires_at > now();
  if s.token is null then raise exception 'not_logged_in'; end if;
  return jsonb_build_object(
    'me', jsonb_build_object('person', s.person_id, 'role', s.role),
    'people', coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'role',role,'email',email,'active',active)) from people), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(to_jsonb(i)) from items i), '[]'::jsonb),
    'settings', coalesce((select value from settings where key = 'site'), '{}'::jsonb)
  );
end $$;
grant execute on function board_fetch(text) to anon, authenticated;

-- aktif oturumlar (yönetici) + oturum kapatma
create or replace function board_sessions(p_token text)
returns jsonb language plpgsql security definer stable as $$
declare s sessions;
begin
  s := board_require(p_token, true);
  return coalesce((select jsonb_agg(jsonb_build_object('person', person_id, 'role', role, 'at', created_at, 'exp', expires_at) order by created_at desc) from sessions where expires_at > now()), '[]'::jsonb);
end $$;
create or replace function board_revoke_person(p_token text, p_person text)
returns void language plpgsql security definer as $$
declare s sessions;
begin
  s := board_require(p_token, true);
  delete from sessions where person_id = p_person and token <> p_token;
end $$;
grant execute on function board_sessions(text), board_revoke_person(text,text) to anon, authenticated;

-- realtime yayını kaldır (anon artık satır göremez; panel 15 sn'de bir yeniler)
do $$ begin alter publication supabase_realtime drop table items; exception when others then null; end $$;
do $$ begin alter publication supabase_realtime drop table people; exception when others then null; end $$;
do $$ begin alter publication supabase_realtime drop table settings; exception when others then null; end $$;
