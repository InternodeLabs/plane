import path from "node:path";
import * as dotenv from "@dotenvx/dotenvx";
import { reactRouter } from "@react-router/dev/vite";
import { defineConfig } from "vite";
import tsconfigPaths from "vite-tsconfig-paths";
import { joinUrlPath } from "@plane/utils";

dotenv.config({ path: path.resolve(__dirname, ".env") });

// Expose only vars starting with VITE_
const viteEnv = Object.keys(process.env)
  .filter((k) => k.startsWith("VITE_"))
  .reduce<Record<string, string>>((a, k) => {
    a[k] = process.env[k] ?? "";
    return a;
  }, {});

const allowedHostsEnv = (process.env.VITE_ALLOWED_HOSTS ?? "god.internode.us,pm.internode.us").trim();
const allowedHosts: true | string[] =
  allowedHostsEnv === "*"
    ? (true as const)
    : allowedHostsEnv
        .split(",")
        .map((h) => h.trim())
        .filter(Boolean);

const basePath = joinUrlPath(process.env.VITE_SPACE_BASE_PATH ?? "", "/") ?? "/";

export default defineConfig(() => ({
  base: basePath,
  define: {
    "process.env": JSON.stringify(viteEnv),
  },
  build: {
    assetsInlineLimit: 0,
  },
  plugins: [reactRouter(), tsconfigPaths({ projects: [path.resolve(__dirname, "tsconfig.json")] })],
  resolve: {
    alias: {
      // Next.js compatibility shims used within space
      "next/link": path.resolve(__dirname, "app/compat/next/link.tsx"),
      "next/navigation": path.resolve(__dirname, "app/compat/next/navigation.ts"),
    },
    dedupe: ["react", "react-dom"],
  },
  server: {
    host: "127.0.0.1",
    allowedHosts,
    headers: {
      "Cache-Control": "no-store, no-cache, must-revalidate",
    },
    proxy: {
      "/uploads": {
        target: "http://127.0.0.1:39000",
        changeOrigin: false,
        secure: false,
      },
    },
  },
}));
