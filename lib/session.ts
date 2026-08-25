import type {Session} from "./types";
const key="sanket-session";
export function getSession():Session|null {if(typeof window==="undefined")return null; const v=localStorage.getItem(key);if(!v)return null;try{const session=JSON.parse(v) as Session;return session.code&&session.playerId&&session.token?session:null}catch{localStorage.removeItem(key);return null}}
export function saveSession(s:Session){localStorage.setItem(key,JSON.stringify(s))}
export function clearSession(){if(typeof window!=="undefined")localStorage.removeItem(key)}
