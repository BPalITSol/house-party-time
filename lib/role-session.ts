import type {RoomRole} from "./types";

export type RoleSession={roomCode:string;role:Exclude<RoomRole,"main_board">;token:string};
type StoredRoleSession=RoleSession&{expiresAt:number};
const key=(roomCode:string,role:RoleSession["role"])=>`partyhouse-role-session:${roomCode}:${role}`;
const sessionDurationMs=12*60*60*1000;

export function getRoleSession(roomCode:string,role:RoleSession["role"]):RoleSession|null{
 if(typeof window==="undefined")return null;
 try{const value=sessionStorage.getItem(key(roomCode,role));if(!value)return null;const session=JSON.parse(value) as StoredRoleSession;if(session.expiresAt<=Date.now()){sessionStorage.removeItem(key(roomCode,role));return null}return session.roomCode===roomCode&&session.role===role&&session.token?{roomCode:session.roomCode,role:session.role,token:session.token}:null}catch{return null}
}
export function saveRoleSession(session:RoleSession){if(typeof window!=="undefined"){localStorage.removeItem(key(session.roomCode,session.role));sessionStorage.setItem(key(session.roomCode,session.role),JSON.stringify({...session,expiresAt:Date.now()+sessionDurationMs}))}}
export function clearRoleSession(roomCode:string,role:RoleSession["role"]){if(typeof window!=="undefined"){localStorage.removeItem(key(roomCode,role));sessionStorage.removeItem(key(roomCode,role))}}
