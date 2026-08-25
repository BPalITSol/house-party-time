-- Phase 0 migration. Run this after 001_initial.sql in the Supabase SQL Editor.
-- Database writes emit an event with no game data; clients re-fetch the
-- role-filtered room_state RPC, so hidden card identities never travel in Realtime payloads.

create or replace function public.set_team(p_code text,p_player_id uuid,p_token uuid,p_team text)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players;r rooms; begin p:=assert_player(p_code,p_player_id,p_token); select * into r from rooms where id=p.room_id for update; if p_team not in ('red','blue') then raise exception 'Invalid team';end if; if r.status<>'lobby' then raise exception 'Teams are locked';end if; update room_players set team=p_team,is_spymaster=false where id=p.id; end $$;

create or replace function public.set_spymaster(p_code text,p_player_id uuid,p_token uuid,p_target_id uuid,p_team text)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players;r rooms; begin p:=assert_player(p_code,p_player_id,p_token); select * into r from rooms where id=p.room_id for update; if p.id<>r.host_player_id then raise exception 'Only the host can choose spymasters';end if; if r.status<>'lobby' then raise exception 'Spymasters are locked after the game starts';end if; if p_team not in ('red','blue') then raise exception 'Invalid team';end if; if not exists(select 1 from room_players where id=p_target_id and room_id=p.room_id and team=p_team) then raise exception 'Choose a player on that team';end if; update room_players set is_spymaster=false where room_id=p.room_id and team=p_team;update room_players set is_spymaster=true where id=p_target_id; end $$;

create or replace function public.start_game(p_code text,p_player_id uuid,p_token uuid,p_words jsonb)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players;r rooms;st text;begin p:=assert_player(p_code,p_player_id,p_token);select * into r from rooms where id=p.room_id for update; if p.id<>r.host_player_id then raise exception 'Only host can start';end if;if r.status<>'lobby' then raise exception 'Game has already started';end if;if (select count(*) from room_players where room_id=r.id and is_spymaster)=2 then else raise exception 'Choose one spymaster for each team';end if;if jsonb_array_length(p_words)<25 then raise exception 'Word pack too small';end if; st:=case when random()<.5 then 'red' else 'blue' end;update rooms set status='playing',active_team=st,cards=make_cards(p_words,st),clue=null,clue_number=null,guesses_left=0,winner=null where id=r.id;end $$;

create or replace function public.submit_clue(p_code text,p_player_id uuid,p_token uuid,p_clue text,p_count int)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players;r rooms;begin p:=assert_player(p_code,p_player_id,p_token);select * into r from rooms where id=p.room_id for update;if r.status<>'playing' or not p.is_spymaster or p.team<>r.active_team or r.clue is not null then raise exception 'Only active spymaster can give a new clue';end if;if length(trim(p_clue))=0 or p_count not between 1 and 9 then raise exception 'Invalid clue';end if;update rooms set clue=trim(p_clue),clue_number=p_count,guesses_left=p_count+1 where id=r.id;end $$;

create or replace function public.pass_turn(p_code text,p_player_id uuid,p_token uuid)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players;r rooms;begin p:=assert_player(p_code,p_player_id,p_token);select * into r from rooms where id=p.room_id for update;if r.status<>'playing' or p.is_spymaster or p.team<>r.active_team or r.clue is null then raise exception 'Only active team may pass after a clue';end if;perform switch_turn(r.id);end $$;

create or replace function public.rematch(p_code text,p_player_id uuid,p_token uuid,p_words jsonb)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players;r rooms;st text;begin p:=assert_player(p_code,p_player_id,p_token);select * into r from rooms where id=p.room_id for update;if p.id<>r.host_player_id then raise exception 'Only host can rematch';end if;if r.status<>'finished' then raise exception 'Finish the current game before a rematch';end if;if jsonb_array_length(p_words)<25 then raise exception 'Word pack too small';end if;st:=case when random()<.5 then 'red' else 'blue' end;update rooms set status='playing',active_team=st,cards=make_cards(p_words,st),clue=null,clue_number=null,guesses_left=0,winner=null where id=r.id;end $$;

create or replace function public.notify_room_change()
returns trigger language plpgsql security definer set search_path=public,realtime as $$
declare room_code text;
begin
  if TG_TABLE_NAME='rooms' then room_code:=coalesce(NEW.code,OLD.code);
  else select code into room_code from rooms where id=coalesce(NEW.room_id,OLD.room_id); end if;
  if room_code is not null then perform realtime.send(jsonb_build_object('room',room_code),'room_changed','room:'||room_code,false); end if;
  return coalesce(NEW,OLD);
end $$;

drop trigger if exists rooms_notify_room_change on public.rooms;
create trigger rooms_notify_room_change after insert or update or delete on public.rooms for each row execute function public.notify_room_change();
drop trigger if exists room_players_notify_room_change on public.room_players;
create trigger room_players_notify_room_change after insert or update or delete on public.room_players for each row execute function public.notify_room_change();
