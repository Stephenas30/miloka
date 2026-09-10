CREATE TABLE public.fanorona_teams (
  team_id text NOT NULL,
  host_id text NOT NULL,
  host_profile jsonb DEFAULT '{}'::jsonb,
  members jsonb DEFAULT '[]'::jsonb,
  status text DEFAULT 'waiting'::text,
  channel_id text,
  merged_source_id text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT fanorona_teams_pkey PRIMARY KEY (team_id)
);