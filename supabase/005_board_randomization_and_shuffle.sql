-- Run after 004_role_gameplay.sql.
-- New boards receive randomized card positions, and an unstarted board can be
-- shuffled again without changing its room, words, role tokens, or card counts.

create or replace function public.make_cards(p_words jsonb,p_start text)
returns jsonb language sql as $$
 with chosen as (
   select value word,row_number() over(order by random()) position
   from jsonb_array_elements(p_words)
   order by random()
   limit 25
 ), typed as (
   select word,case
     when position=1 then 'assassin'
     when position<=case when p_start='red' then 10 else 9 end then p_start
     when position<=18 then case when p_start='red' then 'blue' else 'red' end
     else 'neutral'
   end typ from chosen
 ), shuffled as (
   select word,typ,row_number() over(order by random()) id from typed
 ) select jsonb_agg(jsonb_build_object('id',id,'word',word,'type',typ,'revealed',false) order by id)
 from shuffled $$;

create or replace function public.role_shuffle_board(p_code text)
returns void language plpgsql security definer set search_path=public as $$
declare r rooms; c text:=upper(trim(p_code));
begin
 select * into r from rooms where code=c for update;
 if not found then raise exception 'Room not found'; end if;
 if r.status<>'playing' then raise exception 'The board can only be shuffled during an active game'; end if;
 if r.clue is not null then raise exception 'The board cannot be shuffled after a clue has been given'; end if;
 if exists(select 1 from jsonb_array_elements(r.cards) card where (card->>'revealed')::boolean) then
   raise exception 'The board cannot be shuffled after a card has been revealed';
 end if;

 update rooms set cards=(
   with shuffled as (
     select card,row_number() over(order by random()) new_id
     from jsonb_array_elements(r.cards) card
   ) select jsonb_agg(jsonb_set(card,'{id}',to_jsonb(new_id)) order by new_id)
   from shuffled
 ) where id=r.id;
end $$;

grant execute on function public.role_shuffle_board(text) to anon,authenticated;
