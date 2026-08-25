import type { NextConfig } from "next";
import path from "node:path";
const nextConfig: NextConfig = { reactStrictMode: true, outputFileTracingRoot: path.join(process.cwd()), async headers(){return[{source:"/:path*",headers:[{key:"X-Content-Type-Options",value:"nosniff"},{key:"X-Frame-Options",value:"DENY"},{key:"Referrer-Policy",value:"no-referrer"},{key:"Permissions-Policy",value:"camera=(), microphone=(), geolocation=()"}]}]} };
export default nextConfig;
