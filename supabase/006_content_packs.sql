-- Run after 005_board_randomization_and_shuffle.sql.
-- Adds a room-level word-pack choice without changing the legacy room flow.

alter table public.rooms add column if not exists room_name text;
update public.rooms set room_name='House Party Time' where room_name is null;
alter table public.rooms alter column room_name set default 'House Party Time';
alter table public.rooms alter column room_name set not null;

alter table public.rooms add column if not exists word_pack text;
update public.rooms set word_pack='hindi' where word_pack is null;
alter table public.rooms alter column word_pack set default 'hindi';
alter table public.rooms alter column word_pack set not null;

create or replace function public.role_create_room(p_word_pack text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c text; rid uuid; pid uuid; tok uuid; spy1 uuid; spy2 uuid; pack text:=lower(trim(p_word_pack));
begin
 if pack not in ('hindi','bollywood','desi_mix') then raise exception 'Invalid word pack'; end if;
 loop
   c:='KHEL'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,5));
   exit when not exists(select 1 from rooms where code=c);
 end loop;
 pid:=gen_random_uuid(); tok:=gen_random_uuid();
 insert into rooms(code,host_player_id,room_name,word_pack)
 values(c,pid,'House Party Time',pack)
 returning id,spymaster_1_token,spymaster_2_token into rid,spy1,spy2;
 insert into room_players(id,room_id,nickname,player_token) values(pid,rid,'Main Board',tok);
 return jsonb_build_object('code',c,'player_id',pid,'player_token',tok,'spymaster_1_token',spy1,'spymaster_2_token',spy2,'word_pack',pack);
end $$;

create or replace function public.room_state_for_role(p_code text,p_role_token uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r rooms; role text:='main_board'; secret boolean:=false; visible_cards jsonb; c text:=upper(trim(p_code));
begin
 select * into r from rooms where code=c;
 if not found then raise exception 'Room not found'; end if;
 if p_role_token is not null then
   if p_role_token=r.spymaster_1_token then role:='spymaster_1'; secret:=true;
   elsif p_role_token=r.spymaster_2_token then role:='spymaster_2'; secret:=true;
   else raise exception 'Invalid spymaster access token'; end if;
 end if;
 select coalesce(jsonb_agg(case when secret or (x->>'revealed')::boolean then x else x-'type' end order by (x->>'id')::int),'[]'::jsonb)
 into visible_cards from jsonb_array_elements(r.cards) x;
 return jsonb_build_object(
   'role',role,'code',r.code,'word_pack',r.word_pack,'status',r.status,'active_team',r.active_team,
   'clue',r.clue,'clue_number',r.clue_number,'guesses_left',r.guesses_left,
   'winner',r.winner,'cards',visible_cards
 );
end $$;

grant execute on function public.role_create_room(text) to anon,authenticated;
grant execute on function public.room_state_for_role(text,uuid) to anon,authenticated;
