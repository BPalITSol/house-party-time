"use client";
import {useState} from "react";
import Link from "next/link";
import {supabase,supabaseConfigurationError} from "../lib/supabase";
import {WORD_PACK_LIST,type WordPackId} from "../lib/words";

type Created={code:string;spymaster_1_token:string;spymaster_2_token:string;word_pack:string};
export default function CreateRoleGame(){
 const [created,setCreated]=useState<Created|null>(null),[pack,setPack]=useState<WordPackId>("hindi"),[error,setError]=useState(""),[pending,setPending]=useState(false),[copied,setCopied]=useState("");
 const origin=typeof window==="undefined"?"":window.location.origin;
 const links=created?{main:`${origin}/room/${created.code}`,spy1:`${origin}/room/${created.code}/spymaster-1#token=${created.spymaster_1_token}`,spy2:`${origin}/room/${created.code}/spymaster-2#token=${created.spymaster_2_token}`}:null;
 const selectedPack=WORD_PACK_LIST.find(item=>item.id===pack)!;
 async function create(){
  if(supabaseConfigurationError){setError(supabaseConfigurationError);return}
  setPending(true);setError("");
  try{const {data,error}=await supabase.rpc("role_create_room",{p_word_pack:pack});if(error||!data){setError(error?.message??"Could not create a game.");return}setCreated(data as Created)}
  catch{setError("Could not reach Supabase. Check the project URL, network access, and that the project is running.")}
  finally{setPending(false)}
 }
 async function copy(label:string,value:string){try{await navigator.clipboard.writeText(value);setCopied(label);window.setTimeout(()=>setCopied(""),1800)}catch{setError("Could not copy the link.")}}
 if(!created)return <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-6 p-6"><div><p className="text-sm text-amber-400">HINDI PARTY GAME</p><h1 className="text-5xl font-black">House Party Time</h1><p className="mt-2 text-stone-400">एक शब्द, एक इशारा, अपनी टीम के लिए।</p></div><section><h2 className="mb-3 font-bold">Choose a word pack</h2><div className="space-y-2">{WORD_PACK_LIST.map(item=><button key={item.id} type="button" onClick={()=>setPack(item.id)} className={`block w-full border text-left ${pack===item.id?"border-amber-400 bg-amber-400 text-stone-950":"border-stone-700 bg-stone-900"}`}><span className="block font-bold">{item.name}</span><span className="block text-sm opacity-75">{item.description}</span></button>)}</div><p className="mt-3 text-sm text-stone-400">{selectedPack.words.length} words · locked for this room and its rematches</p></section><button disabled={pending} className="bg-amber-400 text-stone-950" onClick={create}>{pending?"Creating game…":"Create Game"}</button>{error&&<p className="text-red-400">{error}</p>}<Link className="self-start text-sm text-stone-500 underline" href="/about">About Us</Link></main>;
 const row=(step:string,label:string,description:string,href:string,privateLink?:boolean)=><section className="rounded-xl border border-stone-800 bg-stone-900 p-4"><p className="text-xs font-bold uppercase tracking-wide text-amber-400">{step}</p><h2 className="mt-1 font-bold">{label}</h2><p className="mb-3 text-sm text-stone-400">{description}</p><div className="flex flex-wrap gap-2"><a className="rounded-lg bg-amber-400 px-4 py-2 font-semibold text-stone-950" href={href}>{privateLink?"Open Private Screen":"Open Main Board"}</a><button className="bg-stone-700" onClick={()=>void copy(label,href)}>{copied===label?"✓ Copied":"Copy Link"}</button></div></section>;
 return <main className="mx-auto min-h-screen max-w-xl p-6"><p className="text-sm text-amber-400">GAME CREATED</p><h1 className="mt-1 text-4xl font-black">Room {created.code}</h1><p className="mt-2 text-stone-400">{WORD_PACK_LIST.find(item=>item.id===created.word_pack)?.name??"Hindi & Hinglish"} pack selected.</p><section className="mt-5 rounded-xl border border-amber-400/30 bg-amber-400/10 p-4"><h2 className="font-bold">Set up your game</h2><ol className="mt-2 list-decimal space-y-1 pl-5 text-sm text-stone-300"><li>Open the Main Board on the shared screen.</li><li>Send the Red private link to only the Red Spymaster.</li><li>Send the Blue private link to only the Blue Spymaster.</li></ol></section><div className="mt-6 space-y-3">{row("Step 1","Main Board","Open this on the shared screen for all guessers.",links!.main)}{row("Step 2","🔴 Red Spymaster","Private — only this person sees Red and Blue card types.",links!.spy1,true)}{row("Step 3","🔵 Blue Spymaster","Private — only this person sees Red and Blue card types.",links!.spy2,true)}</div>{error&&<p className="mt-4 text-red-400">{error}</p>}</main>
}
