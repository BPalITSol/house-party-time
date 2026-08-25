# House Party Time

A Hindi/Hinglish realtime word-association party game. It is an original project, not affiliated with Codenames.

## Phase 2 features

- Private room code and shareable link; nickname-only entry.
- Team selection, host-controlled spymaster selection and game start.
- Server-generated 5×5 board, synchronized turns/clues/guesses, assassin/win rules and host rematch.
- Hindi + Hinglish word labels.
- Card identities are never returned to ordinary players. Database RPCs enforce all rules; direct table access is blocked by RLS.

## Setup

1. Create a Supabase project, then run [`supabase/001_initial.sql`](supabase/001_initial.sql), [`supabase/002_phase0.sql`](supabase/002_phase0.sql), [`supabase/003_room_role_access.sql`](supabase/003_room_role_access.sql), [`supabase/004_role_gameplay.sql`](supabase/004_role_gameplay.sql), [`supabase/005_board_randomization_and_shuffle.sql`](supabase/005_board_randomization_and_shuffle.sql), [`supabase/006_content_packs.sql`](supabase/006_content_packs.sql), and [`supabase/007_security_hardening.sql`](supabase/007_security_hardening.sql), in that order, in its SQL Editor. Existing Phase 2 databases need the later migrations.
2. Copy `.env.example` to `.env.local` and populate the project URL and anon key from Supabase Connect.
3. Run:

```bash
npm install
npm run dev
```

Open `http://localhost:3000`. Test with two browser profiles/devices. Use `npm run typecheck`, `npm run lint`, and `npm run build` before deployment.

### Security

There are no accounts in this MVP. Spymaster access tokens are stored only in the receiving browser tab and expire after 12 hours. RLS rejects direct reads, and `room_state` removes the hidden `type` field on unrevealed cards for non-spymasters. Never put a Supabase service-role key in `.env.local`.

The Phase 3 role foundation also creates two room-scoped Spymaster UUIDs. Only the `create_room` caller receives them; `room_state_for_role` never returns either token. Calling that RPC without a token returns public Main Board state, while a valid role token returns the complete board for that role.

For a public launch, add server-side rate limiting and CAPTCHA verification. Those require a provider account and secrets, which must be configured only in the hosting environment—not in `.env.local` or browser code.
