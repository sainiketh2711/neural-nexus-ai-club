# NEURAL NEXUS — AI Club Challenge Arena

A fresh, responsive React + Vite experience for a college AI Club event. Designed around one shared college computer per team (about 200 students / 50 teams), with a unique team codename rather than individual student accounts.

## Included
- Futuristic dark UI with responsive layouts
- Unique team-name entry (3–32 letters, numbers, `_` or `-`)
- Five challenge formats: AI quiz, image/vision reasoning, coding, prompt engineering, real-world AI innovation
- Quiz feedback and session score
- Open-response submission forms for code, prompts and innovation proposals
- Team console, leaderboard, organizer console, round-status preview, judge-review queue, CSV export
- Supabase schema/RPC setup file for shared team registrations, server-side sample quiz scoring and shared leaderboard

## Run on your computer
1. Install Node.js LTS.
2. Extract this ZIP and open this folder in VS Code.
3. Open Terminal in this folder and run:

   ```bash
   npm install
   npm run dev
   ```

4. Open the local address Vite prints (usually `http://localhost:5173`).

## Shared logins across different college computers
Without a database configuration, the app is in **browser preview mode**: registrations and scores are saved only in that browser. This is useful for exploring the UI, but it is not suitable for a live event with many computers.

For shared team names and leaderboard:
1. Create a Supabase project.
2. Open its SQL Editor and run `supabase-setup.sql`.
3. Copy the project URL and **anon/public** key into a `.env.local` file in this folder:

   ```env
   VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
   VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
   ```

4. Restart `npm run dev` or rebuild for deployment (`npm run build`). Never put a Supabase service-role key in this file.

## Important live-event limitation
This ZIP is a strong UI + shared-data starter, not a fully secured production competition backend. The supplied SQL protects sample quiz answer keys inside database functions and shares the leaderboard, but event phase changes, authenticated organizer actions, judge grading, server-side timers, full response review across computers, audit logs, and reset controls still need a server-side admin API (for example, a Cloudflare Worker backed by D1). The organizer access code `2077` shown in the prototype is **demo-only** and is not secure because client-side code can be inspected. Do not run a high-stakes event using the demo admin gate alone.

## Deployment
The Vite frontend can be built with `npm run build`; the output is in `dist/`. Deploy `dist/` to Cloudflare Pages or another static host and set the two Vite environment variables in that host's build settings. A production competition should also deploy the protected server-side admin/API described above.

## Event flow suggestion
1. Teams register one unique codename on their assigned system.
2. Organizer opens the waiting room, then starts rounds one at a time.
3. Quiz and vision questions are auto-scored in the sample SQL workflow.
4. Coding, prompt engineering and real-world solution submissions are reviewed against a rubric.
5. Organizer checks the leaderboard, resolves ties, exports results and announces winners.

Questions and rubric should be reviewed by the club organizers before event day. The built-in questions are starter examples and should be expanded for a full-length competition.
