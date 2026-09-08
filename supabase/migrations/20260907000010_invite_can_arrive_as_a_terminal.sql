-- "or on creating you could do the same" — carry the terminal flag on the invite.
--
-- The toggle in 20260907000009 works on a team row, and an invite does not make
-- one: sendInvite writes only an `invitations` row, and the team row appears when
-- somebody accepts. So ticking "this login is a shared terminal" while inviting
-- had nothing to flag.
--
-- One column carries the intent across the gap, and /api/invite/accept applies it
-- when it creates the team row. If the flag is wrong by the time it lands, the
-- toggle on the team row is still there — this only saves a second trip.

begin;

alter table public.invitations
  add column if not exists as_terminal boolean not null default false;

comment on column public.invitations.as_terminal is
  'Ticked while inviting: mark the resulting login as a shared terminal. Applied by /api/invite/accept when it creates the team row, because an invitation has no team row to flag yet.';

commit;
