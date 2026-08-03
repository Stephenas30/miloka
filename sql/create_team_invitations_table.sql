CREATE TABLE IF NOT EXISTS team_invitations (
  id BIGSERIAL PRIMARY KEY,
  inviter_id UUID NOT NULL,
  invitee_id UUID NOT NULL,
  team_id TEXT NOT NULL,
  inviter_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
