CREATE TABLE public.ludo_teams (
  team_id text NOT NULL,
  host_id text NOT NULL,
  host_profile jsonb DEFAULT '{}'::jsonb,
  members jsonb DEFAULT '[]'::jsonb,
  status text DEFAULT 'waiting'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT ludo_teams_pkey PRIMARY KEY (team_id)
);