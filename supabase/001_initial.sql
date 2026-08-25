-- Sanket Phase 2. Run this entire file in the Supabase SQL editor.
create extension if not exists pgcrypto;
create table public.rooms (
  id uuid primary key default gen_random_uuid(), code text unique not null,
  host_player_id uuid not null, status text not null default 'lobby' check(status in ('lobby','playing','finished')),
  active_team text not null default 'red' check(active_team in ('red','blue')),
  clue text, clue_number int, guesses_left int not null default 0, winner text,
  cards jsonb not null default '[]'::jsonb, created_at timestamptz not null default now()
);
create table public.room_players (
 id uuid primary key default gen_random_uuid(), room_id uuid not null references public.rooms(id) on delete cascade,
 nickname text not null check(length(nickname) between 1 and 24), team text check(team in ('red','blue')),
 is_spymaster boolean not null default false, player_token uuid not null default gen_random_uuid(), created_at timestamptz not null default now(),
 unique(room_id,id)
);
alter table public.rooms enable row level security; alter table public.room_players enable row level security;
-- No client table policies. The functions below are the only API.

create or replace function public.assert_player(p_code text,p_player_id uuid,p_token uuid)
returns public.room_players language plpgsql security definer set search_path=public as $$
declare p public.room_players;
begin select rp.* into p from room_players rp join rooms r on r.id=rp.room_id where r.code=upper(p_code) and rp.id=p_player_id and rp.player_token=p_token;
 if not found then raise exception 'Invalid room session'; end if; return p; end $$;

create or replace function public.create_room(p_nickname text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c text; rid uuid; pid uuid; tok uuid;
begin
 if length(trim(p_nickname))=0 then raise exception 'Nickname is required'; end if;
 loop c:='KHEL'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,5)); exit when not exists(select 1 from rooms where code=c); end loop;
 pid:=gen_random_uuid(); tok:=gen_random_uuid(); insert into rooms(code,host_player_id) values(c,pid) returning id into rid;
 insert into room_players(id,room_id,nickname,player_token) values(pid,rid,trim(p_nickname),tok);
 return jsonb_build_object('code',c,'player_id',pid,'player_token',tok);
end $$;
create or replace function public.join_room(p_code text,p_nickname text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare rid uuid; pid uuid:=gen_random_uuid();tok uuid:=gen_random_uuid();c text:=upper(trim(p_code));
begin select id into rid from rooms where code=c; if not found then raise exception 'Room not found'; end if;
 if length(trim(p_nickname))=0 then raise exception 'Nickname is required';end if;
 insert into room_players(id,room_id,nickname,player_token) values(pid,rid,trim(p_nickname),tok);
 return jsonb_build_object('code',c,'player_id',pid,'player_token',tok); end $$;

create or replace function public.room_state(p_code text,p_player_id uuid,p_token uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare p room_players; r rooms; secret boolean; visible_cards jsonb;
begin p:=assert_player(p_code,p_player_id,p_token); select * into r from rooms where id=p.room_id; secret:=p.is_spymaster;
 select coalesce(jsonb_agg(case when secret or (x->>'revealed')::boolean then x else x-'type' end order by (x->>'id')::int),'[]') into visible_cards from jsonb_array_elements(r.cards) x;
 return jsonb_build_object('code',r.code,'status',r.status,'host_player_id',r.host_player_id,'active_team',r.active_team,'clue',r.clue,'clue_number',r.clue_number,'guesses_left',r.guesses_left,'winner',r.winner,'cards',visible_cards,
 'players',(select jsonb_agg(jsonb_build_object('id',rp.id,'nickname',rp.nickname,'team',rp.team,'is_spymaster',rp.is_spymaster,'is_host',rp.id=r.host_player_id) order by rp.created_at) from room_players rp where rp.room_id=r.id)); end $$;

create or replace function public.set_team(p_code text,p_player_id uuid,p_token uuid,p_team text)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players; begin p:=assert_player(p_code,p_player_id,p_token); if p_team not in ('red','blue') then raise exception 'Invalid team';end if; if (select status from rooms where id=p.room_id)<>'lobby' then raise exception 'Teams are locked';end if; update room_players set team=p_team,is_spymaster=false where id=p.id; end $$;
create or replace function public.set_spymaster(p_code text,p_player_id uuid,p_token uuid,p_target_id uuid,p_team text)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players; begin p:=assert_player(p_code,p_player_id,p_token); if p.id<>(select host_player_id from rooms where id=p.room_id) then raise exception 'Only the host can choose spymasters';end if; if (select status from rooms where id=p.room_id)<>'lobby' then raise exception 'Spymasters are locked after the game starts';end if; if p_team not in ('red','blue') then raise exception 'Invalid team';end if; if not exists(select 1 from room_players where id=p_target_id and room_id=p.room_id and team=p_team) then raise exception 'Choose a player on that team';end if; update room_players set is_spymaster=false where room_id=p.room_id and team=p_team;update room_players set is_spymaster=true where id=p_target_id; end $$;

create or replace function public.make_cards(p_words jsonb,p_start text) returns jsonb language sql as $$
 with chosen as (select value word,row_number()over(order by random()) n from jsonb_array_elements(p_words) limit 25), typed as (select n,word,case when n=1 then 'assassin' when n<=case when p_start='red' then 10 else 9 end then p_start when n<=18 then case when p_start='red' then 'blue' else 'red' end else 'neutral' end typ from chosen) select jsonb_agg(jsonb_build_object('id',n,'word',word,'type',typ,'revealed',false) order by n) from typed $$;
create or replace function public.start_game(p_code text,p_player_id uuid,p_token uuid,p_words jsonb)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players;r rooms;st text;begin p:=assert_player(p_code,p_player_id,p_token);select * into r from rooms where id=p.room_id for update; if p.id<>r.host_player_id then raise exception 'Only host can start';end if;if r.status<>'lobby' then raise exception 'Game has already started';end if;if (select count(*) from room_players where room_id=r.id and is_spymaster)=2 then else raise exception 'Choose one spymaster for each team';end if;if jsonb_array_length(p_words)<25 then raise exception 'Word pack too small';end if; st:=case when random()<.5 then 'red' else 'blue' end;update rooms set status='playing',active_team=st,cards=make_cards(p_words,st),clue=null,clue_number=null,guesses_left=0,winner=null where id=r.id;end $$;

create or replace function public.submit_clue(p_code text,p_player_id uuid,p_token uuid,p_clue text,p_count int)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players;r rooms;begin p:=assert_player(p_code,p_player_id,p_token);select * into r from rooms where id=p.room_id for update;if r.status<>'playing' or not p.is_spymaster or p.team<>r.active_team or r.clue is not null then raise exception 'Only active spymaster can give a new clue';end if;if length(trim(p_clue))=0 or p_count not between 1 and 9 then raise exception 'Invalid clue';end if;update rooms set clue=trim(p_clue),clue_number=p_count,guesses_left=p_count+1 where id=r.id;end $$;
create or replace function public.switch_turn(rid uuid) returns void language plpgsql security definer set search_path=public as $$ begin update rooms set active_team=case when active_team='red' then 'blue' else 'red' end,clue=null,clue_number=null,guesses_left=0 where id=rid;end $$;
create or replace function public.pass_turn(p_code text,p_player_id uuid,p_token uuid)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players;r rooms;begin p:=assert_player(p_code,p_player_id,p_token);select * into r from rooms where id=p.room_id for update;if r.status<>'playing' or p.is_spymaster or p.team<>r.active_team or r.clue is null then raise exception 'Only active team may pass after a clue';end if;perform switch_turn(r.id);end $$;
create or replace function public.guess_card(p_code text,p_player_id uuid,p_token uuid,p_card_id int)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players;r rooms;c jsonb;typ text;remaining int;begin p:=assert_player(p_code,p_player_id,p_token);select * into r from rooms where id=p.room_id for update;if r.status<>'playing' or p.is_spymaster or p.team<>r.active_team or r.clue is null then raise exception 'Not allowed to guess';end if;select x into c from jsonb_array_elements(r.cards)x where (x->>'id')::int=p_card_id;if c is null or (c->>'revealed')::boolean then raise exception 'Card unavailable';end if;typ:=c->>'type';update rooms set cards=(select jsonb_agg(case when (x->>'id')::int=p_card_id then jsonb_set(x,'{revealed}','true') else x end order by (x->>'id')::int) from jsonb_array_elements(r.cards)x) where id=r.id;
 if typ='assassin' then update rooms set status='finished',winner=case when r.active_team='red' then 'blue' else 'red' end where id=r.id;return;end if;
 select count(*) into remaining from jsonb_array_elements((select cards from rooms where id=r.id))x where x->>'type'=r.active_team and not (x->>'revealed')::boolean;if remaining=0 then update rooms set status='finished',winner=r.active_team where id=r.id;return;end if;
 if typ<>r.active_team then perform switch_turn(r.id);else update rooms set guesses_left=guesses_left-1 where id=r.id;if (select guesses_left from rooms where id=r.id)<=0 then perform switch_turn(r.id);end if;end if;end $$;
create or replace function public.rematch(p_code text,p_player_id uuid,p_token uuid,p_words jsonb)
returns void language plpgsql security definer set search_path=public as $$ declare p room_players;r rooms;st text;begin p:=assert_player(p_code,p_player_id,p_token);select * into r from rooms where id=p.room_id for update;if p.id<>r.host_player_id then raise exception 'Only host can rematch';end if;if r.status<>'finished' then raise exception 'Finish the current game before a rematch';end if;if jsonb_array_length(p_words)<25 then raise exception 'Word pack too small';end if;st:=case when random()<.5 then 'red' else 'blue' end;update rooms set status='playing',active_team=st,cards=make_cards(p_words,st),clue=null,clue_number=null,guesses_left=0,winner=null where id=r.id;end $$;
grant execute on all functions in schema public to anon,authenticated;
