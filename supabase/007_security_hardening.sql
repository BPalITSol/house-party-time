-- Run after 006_content_packs.sql.
-- Enforces the app's fair-clue rules and rejects malformed word-pack input.

create or replace function public.assert_role_word_pack(p_words jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare total int; distinct_hi int; malformed int;
begin
 if jsonb_typeof(p_words)<>'array' or jsonb_array_length(p_words)<>100 then
   raise exception 'A complete 100-word pack is required';
 end if;
 select count(*),count(distinct lower(trim(word->>'hi'))),count(*) filter(where coalesce(trim(word->>'hi'),'')='' or coalesce(trim(word->>'roman'),'')='')
 into total,distinct_hi,malformed from jsonb_array_elements(p_words) word;
 if total<>100 or distinct_hi<>100 or malformed<>0 then raise exception 'Invalid word pack'; end if;
end $$;

create or replace function public.role_start_game(p_code text,p_words jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; st text; c text:=upper(trim(p_code));
begin
 perform assert_role_word_pack(p_words);
 select * into r from rooms where code=c for update;
 if not found then raise exception 'Room not found'; end if;
 if r.status<>'lobby' then raise exception 'Game has already started'; end if;
 st:=case when random()<.5 then 'red' else 'blue' end;
 update rooms set status='playing',active_team=st,cards=make_cards(p_words,st),clue=null,clue_number=null,guesses_left=0,winner=null where id=r.id;
end $$;

create or replace function public.role_rematch(p_code text,p_words jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; st text; c text:=upper(trim(p_code));
begin
 perform assert_role_word_pack(p_words);
 select * into r from rooms where code=c for update;
 if not found then raise exception 'Room not found'; end if;
 if r.status<>'finished' then raise exception 'Finish the current game before a rematch'; end if;
 st:=case when random()<.5 then 'red' else 'blue' end;
 update rooms set status='playing',active_team=st,cards=make_cards(p_words,st),clue=null,clue_number=null,guesses_left=0,winner=null where id=r.id;
end $$;

create or replace function public.role_submit_clue(p_code text,p_spymaster_token uuid,p_clue text,p_count int)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; team text; c text:=upper(trim(p_code)); clue_text text:=coalesce(trim(p_clue),'');
begin
 select * into r from rooms where code=c for update;
 if not found then raise exception 'Room not found'; end if;
 if p_spymaster_token=r.spymaster_1_token then team:='red';
 elsif p_spymaster_token=r.spymaster_2_token then team:='blue';
 else raise exception 'Invalid spymaster access token'; end if;
 if r.status<>'playing' or team<>r.active_team or r.clue is not null then raise exception 'Only the active spymaster can give a new clue'; end if;
 if clue_text='' or clue_text~'[[:space:]]' or p_count not between 1 and 9 then raise exception 'Use one word and a number from 1 to 9'; end if;
 if exists(select 1 from jsonb_array_elements(r.cards) card where not (card->>'revealed')::boolean and (lower(card->'word'->>'hi')=lower(clue_text) or lower(card->'word'->>'roman')=lower(clue_text))) then
   raise exception 'A clue cannot be an unrevealed card word';
 end if;
 update rooms set clue=clue_text,clue_number=p_count,guesses_left=p_count+1 where id=r.id;
end $$;

grant execute on function public.assert_role_word_pack(jsonb) to anon,authenticated;
grant execute on function public.role_start_game(text,jsonb) to anon,authenticated;
grant execute on function public.role_rematch(text,jsonb) to anon,authenticated;
grant execute on function public.role_submit_clue(text,uuid,text,int) to anon,authenticated;
