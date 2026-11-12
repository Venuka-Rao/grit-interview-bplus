# GitHub and Vercel setup

1. Clone this private repository.
2. Install Node.js 22.12 or newer.
3. Copy `.env.example` to `.env.local`.
4. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` to the dedicated B+ demo project.
5. Run `npm install`, then `npm run dev` or `npm run build`.

The `pre-build` bootstrap `scripts/restore-source.cjs` restores the compressed source bundle into the normal project tree before Vite runs. This compact source packaging is used for the initial repository handoff; the restored files are normal editable HTML, JavaScript, SQL and Markdown files in the working project.

## Deploy to Vercel

1. Vercel → Add New → Project → Import `Venuka-Rao/grit-interview-bplus`.
2. Framework preset: Vite.
3. Build command: `npm run build`.
4. Output directory: `dist`.
5. Add the two environment variables above to Production (and Preview if needed).
6. Deploy.

Do not put Supabase secret or service-role keys in frontend code or `VITE_*` variables.

## Demo safety

This is a synthetic public demo with a selectable role switcher. It is not an authentication or authorization model for real students. Do not enter actual NIAT data. Configure CAPTCHA/Turnstile and appropriate abuse controls before sharing the URL broadly.
