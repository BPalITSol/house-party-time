import RoleGame from "../../../../components/RoleGame";
export default async function SpymasterTwoPage({params}:{params:Promise<{code:string}>}){const {code}=await params;return <RoleGame code={code} role="spymaster_2"/>}
