"use client";
import {useState} from "react";
import Link from "next/link";
import Game from "../../components/Game";
import {supabase} from "../../lib/supabase";
import {clearSession,saveSession} from "../../lib/session";
import type {Session} from "../../lib/types";

export default function LegacyPage(){const [name,setName]=useState(""),[code,setCode]=useState(""),[session,setSession]=useState<Session|null>(null),[error,setError]=useState("");async function enter(fn:"create_room"|"join_room"){if(!name.trim())return setError("Enter a nickname first.");const {data,error}=await supabase.rpc(fn,fn==="create_room"?{p_nickname:name.trim()}:{p_code:code.trim().toUpperCase(),p_nickname:name.trim()});if(error||!data)return setError(error?.message??"Could not enter room.");const next={code:data.code,playerId:data.player_id,token:data.player_token};saveSession(next);setSession(next)}if(session)return <Game session={session} onInvalidSession={()=>{clearSession();setSession(null)}}/>;return <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-4 p-6"><h1 className="text-3xl font-black">Legacy MVP</h1><input value={name} onChange={e=>setName(e.target.value)} placeholder="Nickname"/><button className="bg-amber-400 text-stone-950" onClick={()=>void enter("create_room")}>Create legacy room</button><input value={code} onChange={e=>setCode(e.target.value)} placeholder="Room code"/><button className="bg-sky-500" onClick={()=>void enter("join_room")}>Join legacy room</button>{error&&<p className="text-red-400">{error}</p>}<Link className="text-sm text-stone-400 underline" href="/">Back to new game</Link></main>}
