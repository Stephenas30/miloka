CREATE TABLE public.private_matches (
  match_code TEXT NOT NULL,
  team_a_id TEXT NOT NULL,
  team_a_host_id TEXT NOT NULL,
  team_a_host_profile JSONB DEFAULT '{}'::jsonb,
  team_a_guest_id TEXT,
  team_a_guest_profile JSONB DEFAULT '{}'::jsonb,
  team_b_id TEXT,
  team_b_host_id TEXT,
  team_b_host_profile JSONB DEFAULT '{}'::jsonb,
  team_b_guest_id TEXT,
  team_b_guest_profile JSONB DEFAULT '{}'::jsonb,
  status TEXT DEFAULT 'waiting'::text,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  CONSTRAINT private_matches_pkey PRIMARY KEY (match_code),
  CONSTRAINT private_matches_team_a_id_fkey FOREIGN KEY (team_a_id) REFERENCES public.teams(team_id),
  CONSTRAINT private_matches_team_b_id_fkey FOREIGN KEY (team_b_id) REFERENCES public.teams(team_id)
);

CREATE INDEX idx_private_matches_status ON private_matches (status);
CREATE INDEX idx_private_matches_team_a ON private_matches (team_a_id);
CREATE INDEX idx_private_matches_team_b ON private_matches (team_b_id);
