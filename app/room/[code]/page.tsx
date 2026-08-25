import RoleGame from "../../../components/RoleGame";
export default async function RoomPage({params}:{params:Promise<{code:string}>}){const {code}=await params;return <RoleGame code={code} role="main_board"/>}
