-- Three-screen foundation. Run after 001_initial.sql and 002_phase0.sql.
-- This migration adds room-scoped Spymaster credentials without changing the
-- existing player-based game flow or gameplay RPC authorization.

alter table public.rooms add column if not exists spymaster_1_token uuid;
alter table public.rooms add column if not exists spymaster_2_token uuid;
update public.rooms set spymaster_1_token=gen_random_uuid() where spymaster_1_token is null;
update public.rooms set spymaster_2_token=gen_random_uuid() where spymaster_2_token is null;
alter table public.rooms alter column spymaster_1_token set default gen_random_uuid();
alter table public.rooms alter column spymaster_2_token set default gen_random_uuid();
alter table public.rooms alter column spymaster_1_token set not null;
alter table public.rooms alter column spymaster_2_token set not null;

-- The creator is the only caller that receives the two private role tokens.
-- Existing clients ignore the additional JSON fields and retain their player session.
create or replace function public.create_room(p_nickname text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c text; rid uuid; pid uuid; tok uuid; spy1 uuid; spy2 uuid;
begin
 if length(trim(p_nickname))=0 then raise exception 'Nickname is required'; end if;
 loop c:='KHEL'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,5)); exit when not exists(select 1 from rooms where code=c); end loop;
 pid:=gen_random_uuid(); tok:=gen_random_uuid();
 insert into rooms(code,host_player_id) values(c,pid) returning id,spymaster_1_token,spymaster_2_token into rid,spy1,spy2;
 insert into room_players(id,room_id,nickname,player_token) values(pid,rid,trim(p_nickname),tok);
 return jsonb_build_object('code',c,'player_id',pid,'player_token',tok,'spymaster_1_token',spy1,'spymaster_2_token',spy2);
end $$;

-- No token is public Main Board access. Supplying any non-null invalid token is
-- an authorization failure rather than a silent downgrade to public access.
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
   'role',role,'code',r.code,'status',r.status,'active_team',r.active_team,
   'clue',r.clue,'clue_number',r.clue_number,'guesses_left',r.guesses_left,
   'winner',r.winner,'cards',visible_cards
 );
end $$;

grant execute on function public.room_state_for_role(text,uuid) to anon,authenticated;
