-- Three-role gameplay foundation. Run after 003_room_role_access.sql.
-- These RPCs intentionally coexist with the legacy player-based RPCs.

create or replace function public.role_start_game(p_code text,p_words jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; st text; c text:=upper(trim(p_code));
begin
 select * into r from rooms where code=c for update;
 if not found then raise exception 'Room not found'; end if;
 if r.status<>'lobby' then raise exception 'Game has already started'; end if;
 if jsonb_array_length(p_words)<25 then raise exception 'Word pack too small'; end if;
 st:=case when random()<.5 then 'red' else 'blue' end;
 update rooms set status='playing',active_team=st,cards=make_cards(p_words,st),clue=null,clue_number=null,guesses_left=0,winner=null where id=r.id;
end $$;

create or replace function public.role_submit_clue(p_code text,p_spymaster_token uuid,p_clue text,p_count int)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; team text; c text:=upper(trim(p_code));
begin
 select * into r from rooms where code=c for update;
 if not found then raise exception 'Room not found'; end if;
 if p_spymaster_token=r.spymaster_1_token then team:='red';
 elsif p_spymaster_token=r.spymaster_2_token then team:='blue';
 else raise exception 'Invalid spymaster access token'; end if;
 if r.status<>'playing' or team<>r.active_team or r.clue is not null then raise exception 'Only the active spymaster can give a new clue'; end if;
 if length(trim(p_clue))=0 or p_count not between 1 and 9 then raise exception 'Invalid clue'; end if;
 update rooms set clue=trim(p_clue),clue_number=p_count,guesses_left=p_count+1 where id=r.id;
end $$;

create or replace function public.role_guess_card(p_code text,p_card_id int)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; c jsonb; typ text; remaining int; room_code text:=upper(trim(p_code));
begin
 select * into r from rooms where code=room_code for update;
 if not found then raise exception 'Room not found'; end if;
 if r.status<>'playing' or r.clue is null then raise exception 'Not allowed to guess'; end if;
 select x into c from jsonb_array_elements(r.cards)x where (x->>'id')::int=p_card_id;
 if c is null or (c->>'revealed')::boolean then raise exception 'Card unavailable'; end if;
 typ:=c->>'type';
 update rooms set cards=(select jsonb_agg(case when (x->>'id')::int=p_card_id then jsonb_set(x,'{revealed}','true') else x end order by (x->>'id')::int) from jsonb_array_elements(r.cards)x) where id=r.id;
 if typ='assassin' then
   update rooms set status='finished',winner=case when r.active_team='red' then 'blue' else 'red' end where id=r.id;
   return;
 end if;
 select count(*) into remaining from jsonb_array_elements((select cards from rooms where id=r.id))x where x->>'type'=r.active_team and not (x->>'revealed')::boolean;
 if remaining=0 then
   update rooms set status='finished',winner=r.active_team where id=r.id;
   return;
 end if;
 if typ<>r.active_team then
   perform switch_turn(r.id);
 else
   update rooms set guesses_left=guesses_left-1 where id=r.id;
   if (select guesses_left from rooms where id=r.id)<=0 then perform switch_turn(r.id); end if;
 end if;
end $$;

create or replace function public.role_pass_turn(p_code text)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; c text:=upper(trim(p_code));
begin
 select * into r from rooms where code=c for update;
 if not found then raise exception 'Room not found'; end if;
 if r.status<>'playing' or r.clue is null then raise exception 'A turn can only be passed after a clue'; end if;
 perform switch_turn(r.id);
end $$;

create or replace function public.role_rematch(p_code text,p_words jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; st text; c text:=upper(trim(p_code));
begin
 select * into r from rooms where code=c for update;
 if not found then raise exception 'Room not found'; end if;
 if r.status<>'finished' then raise exception 'Finish the current game before a rematch'; end if;
 if jsonb_array_length(p_words)<25 then raise exception 'Word pack too small'; end if;
 st:=case when random()<.5 then 'red' else 'blue' end;
 update rooms set status='playing',active_team=st,cards=make_cards(p_words,st),clue=null,clue_number=null,guesses_left=0,winner=null where id=r.id;
end $$;

grant execute on function public.role_start_game(text,jsonb) to anon,authenticated;
grant execute on function public.role_submit_clue(text,uuid,text,int) to anon,authenticated;
grant execute on function public.role_guess_card(text,int) to anon,authenticated;
grant execute on function public.role_pass_turn(text) to anon,authenticated;
grant execute on function public.role_rematch(text,jsonb) to anon,authenticated;
