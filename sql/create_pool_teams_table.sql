CREATE TABLE IF NOT EXISTS public.pool_teams (
  team_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  host_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
  guest_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  guest_profile JSONB NOT NULL DEFAULT '{}'::jsonb,
  access_type TEXT NOT NULL CHECK (access_type IN ('friend', 'public')),
  status TEXT NOT NULL CHECK (
    status IN ('waiting', 'public_waiting', 'matched', 'playing', 'cancelled')
  ),
  join_code TEXT,
  matched_team_id UUID REFERENCES public.pool_teams(team_id),
  game_seed BIGINT,
  winner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  settled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (host_id <> guest_id)
);

ALTER TABLE public.pool_teams
  ADD COLUMN IF NOT EXISTS winner_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.pool_teams
  ADD COLUMN IF NOT EXISTS settled_at TIMESTAMPTZ;
ALTER TABLE public.pool_teams
  ADD COLUMN IF NOT EXISTS join_code TEXT;

DO $$
DECLARE
  current_team RECORD;
  generated_code TEXT;
BEGIN
  FOR current_team IN
    SELECT team_id
    FROM public.pool_teams
    WHERE join_code IS NULL
  LOOP
    LOOP
      generated_code := lpad(floor(random() * 1000000)::INTEGER::TEXT, 6, '0');
      UPDATE public.pool_teams
      SET join_code = generated_code
      WHERE team_id = current_team.team_id
        AND NOT EXISTS (
          SELECT 1
          FROM public.pool_teams existing
          WHERE existing.join_code = generated_code
        );
      EXIT WHEN FOUND;
    END LOOP;
  END LOOP;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pool_teams_join_code
  ON public.pool_teams (join_code)
  WHERE join_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pool_teams_public_queue
  ON public.pool_teams (created_at)
  WHERE access_type = 'public' AND status = 'public_waiting';

ALTER TABLE public.pool_teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pool_teams REPLICA IDENTITY FULL;

DROP POLICY IF EXISTS pool_teams_read_authenticated ON public.pool_teams;
CREATE POLICY pool_teams_read_authenticated
  ON public.pool_teams FOR SELECT TO authenticated
  USING (
    auth.uid() = host_id
    OR auth.uid() = guest_id
  );
GRANT SELECT ON public.pool_teams TO authenticated;

ALTER TABLE public.team_invitations
  ADD COLUMN IF NOT EXISTS game_type TEXT NOT NULL DEFAULT 'belote';

ALTER TABLE public.team_invitations
  DROP CONSTRAINT IF EXISTS team_invitations_team_id_fkey;

CREATE OR REPLACE FUNCTION public.create_pool_team(
  p_host_profile JSONB,
  p_access_type TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  new_team_id UUID;
  new_join_code TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_access_type NOT IN ('friend', 'public') THEN
    RAISE EXCEPTION 'Invalid access type';
  END IF;

  LOOP
    new_join_code := lpad(floor(random() * 1000000)::INTEGER::TEXT, 6, '0');
    BEGIN
      INSERT INTO public.pool_teams (
        host_id, host_profile, access_type, status, join_code
      )
      VALUES (
        auth.uid(),
        COALESCE(p_host_profile, '{}'::jsonb) ||
          jsonb_build_object('bet', 0, 'bet_agreed', FALSE),
        p_access_type,
        CASE WHEN p_access_type = 'public' THEN 'public_waiting' ELSE 'waiting' END,
        new_join_code
      )
      RETURNING team_id INTO new_team_id;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      new_team_id := NULL;
    END;
  END LOOP;

  RETURN new_team_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.join_pool_team_by_code(
  p_join_code TEXT,
  p_guest_profile JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  joined_team_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_join_code IS NULL OR p_join_code !~ '^[0-9]{6}$' THEN
    RETURN NULL;
  END IF;

  UPDATE public.pool_teams
  SET guest_id = auth.uid(),
      guest_profile = COALESCE(p_guest_profile, '{}'::jsonb) ||
        jsonb_build_object('bet', 0, 'bet_agreed', FALSE),
      status = 'matched',
      updated_at = now()
  WHERE join_code = p_join_code
    AND access_type = 'friend'
    AND status = 'waiting'
    AND guest_id IS NULL
    AND host_id <> auth.uid()
  RETURNING team_id INTO joined_team_id;

  RETURN joined_team_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.join_pool_team(
  p_team_id UUID,
  p_guest_profile JSONB,
  p_invitation_id BIGINT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  joined BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF p_invitation_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.team_invitations
    JOIN public.pool_teams ON pool_teams.team_id = p_team_id
    WHERE team_invitations.id = p_invitation_id
      AND team_invitations.invitee_id = auth.uid()
      AND team_invitations.team_id = p_team_id::TEXT
      AND team_invitations.game_type = 'billard'
      AND team_invitations.status = 'pending'
      AND team_invitations.inviter_id = pool_teams.host_id
  ) THEN
    RETURN FALSE;
  END IF;

  UPDATE public.pool_teams
  SET guest_id = auth.uid(),
      guest_profile = COALESCE(p_guest_profile, '{}'::jsonb) ||
        jsonb_build_object('bet', 0, 'bet_agreed', FALSE),
      status = 'matched',
      updated_at = now()
  WHERE team_id = p_team_id
    AND guest_id IS NULL
    AND host_id <> auth.uid()
    AND (
      (p_invitation_id IS NOT NULL AND access_type = 'friend' AND status = 'waiting')
      OR
      (p_invitation_id IS NULL AND access_type = 'public' AND status = 'public_waiting')
    );

  joined := FOUND;
  IF joined AND p_invitation_id IS NOT NULL THEN
    UPDATE public.team_invitations
    SET status = 'accepted'
    WHERE id = p_invitation_id;
  END IF;

  RETURN joined;
END;
$$;

CREATE OR REPLACE FUNCTION public.try_match_pool_team(p_team_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  current_room public.pool_teams%ROWTYPE;
  opponent public.pool_teams%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT * INTO current_room
  FROM public.pool_teams
  WHERE team_id = p_team_id
  FOR UPDATE;

  IF NOT FOUND
     OR current_room.host_id <> auth.uid()
     OR current_room.status <> 'public_waiting' THEN
    RETURN NULL;
  END IF;

  SELECT * INTO opponent
  FROM public.pool_teams
  WHERE access_type = 'public'
    AND status = 'public_waiting'
    AND guest_id IS NULL
    AND created_at > now() - interval '90 seconds'
    AND team_id <> current_room.team_id
    AND host_id <> auth.uid()
  ORDER BY created_at, team_id
  LIMIT 1
  FOR UPDATE SKIP LOCKED;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  UPDATE public.pool_teams
  SET guest_id = opponent.host_id,
      guest_profile = COALESCE(opponent.host_profile, '{}'::jsonb) ||
        jsonb_build_object('bet', 0, 'bet_agreed', FALSE),
      status = 'matched',
      updated_at = now()
  WHERE team_id = current_room.team_id;

  UPDATE public.pool_teams
  SET status = 'cancelled',
      matched_team_id = current_room.team_id,
      updated_at = now()
  WHERE team_id = opponent.team_id;

  RETURN current_room.team_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.start_pool_team(
  p_team_id UUID,
  p_game_seed BIGINT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  current_team public.pool_teams%ROWTYPE;
  host_bet INTEGER;
  guest_bet INTEGER;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT * INTO current_team
  FROM public.pool_teams
  WHERE team_id = p_team_id
  FOR UPDATE;

  IF NOT FOUND
     OR current_team.host_id <> auth.uid()
     OR current_team.guest_id IS NULL
     OR current_team.status <> 'matched' THEN
    RETURN FALSE;
  END IF;

  host_bet := COALESCE((current_team.host_profile->>'bet')::INTEGER, 0);
  guest_bet := COALESCE((current_team.guest_profile->>'bet')::INTEGER, 0);
  IF (host_bet > 0 OR guest_bet > 0)
     AND (
       COALESCE((current_team.host_profile->>'bet_agreed')::BOOLEAN, FALSE) = FALSE
       OR COALESCE((current_team.guest_profile->>'bet_agreed')::BOOLEAN, FALSE) = FALSE
     ) THEN
    RETURN FALSE;
  END IF;

  UPDATE public.pool_teams
  SET status = 'playing',
      game_seed = p_game_seed,
      updated_at = now()
  WHERE team_id = p_team_id
    AND host_id = auth.uid()
    AND status = 'matched';

  RETURN FOUND;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_pool_team_bet(
  p_team_id UUID,
  p_bet INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  current_team public.pool_teams%ROWTYPE;
  current_profile JSONB;
  available_coins INTEGER;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_bet IS NULL OR p_bet < 0 THEN
    RAISE EXCEPTION 'Invalid bet amount';
  END IF;

  SELECT * INTO current_team
  FROM public.pool_teams
  WHERE team_id = p_team_id
  FOR UPDATE;

  IF NOT FOUND
     OR current_team.status <> 'matched'
     OR auth.uid() NOT IN (current_team.host_id, current_team.guest_id) THEN
    RETURN FALSE;
  END IF;

  current_profile := CASE
    WHEN auth.uid() = current_team.host_id THEN current_team.host_profile
    ELSE current_team.guest_profile
  END;
  IF COALESCE((current_profile->>'bet')::INTEGER, 0) = p_bet THEN
    RETURN TRUE;
  END IF;

  SELECT COALESCE(coins, 0) INTO available_coins
  FROM public.users
  WHERE id = auth.uid()
  FOR UPDATE;

  IF p_bet > COALESCE(available_coins, 0) THEN
    RAISE EXCEPTION 'Bet exceeds available coins';
  END IF;

  IF auth.uid() = current_team.host_id THEN
    UPDATE public.pool_teams
    SET host_profile = jsonb_set(
          COALESCE(host_profile, '{}'::jsonb),
          '{bet}',
          to_jsonb(p_bet),
          TRUE
        ) || jsonb_build_object('bet_agreed', FALSE),
        guest_profile = COALESCE(guest_profile, '{}'::jsonb) ||
          jsonb_build_object('bet_agreed', FALSE),
        updated_at = now()
    WHERE team_id = p_team_id;
  ELSE
    UPDATE public.pool_teams
    SET guest_profile = jsonb_set(
          COALESCE(guest_profile, '{}'::jsonb),
          '{bet}',
          to_jsonb(p_bet),
          TRUE
        ) || jsonb_build_object('bet_agreed', FALSE),
        host_profile = COALESCE(host_profile, '{}'::jsonb) ||
          jsonb_build_object('bet_agreed', FALSE),
        updated_at = now()
    WHERE team_id = p_team_id;
  END IF;

  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_pool_team_bet_agreement(
  p_team_id UUID,
  p_agreed BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  current_team public.pool_teams%ROWTYPE;
  current_profile JSONB;
  available_coins INTEGER;
  current_bet INTEGER;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  SELECT * INTO current_team
  FROM public.pool_teams
  WHERE team_id = p_team_id
  FOR UPDATE;

  IF NOT FOUND
     OR current_team.status <> 'matched'
     OR auth.uid() NOT IN (current_team.host_id, current_team.guest_id) THEN
    RETURN FALSE;
  END IF;

  current_profile := CASE
    WHEN auth.uid() = current_team.host_id THEN current_team.host_profile
    ELSE current_team.guest_profile
  END;
  current_bet := COALESCE((current_profile->>'bet')::INTEGER, 0);

  IF p_agreed AND current_bet > 0 THEN
    SELECT COALESCE(coins, 0) INTO available_coins
    FROM public.users
    WHERE id = auth.uid()
    FOR UPDATE;

    IF current_bet > COALESCE(available_coins, 0) THEN
      RAISE EXCEPTION 'Bet exceeds available coins';
    END IF;
  END IF;

  IF auth.uid() = current_team.host_id THEN
    UPDATE public.pool_teams
    SET host_profile = jsonb_set(
          COALESCE(host_profile, '{}'::jsonb),
          '{bet_agreed}',
          to_jsonb(p_agreed),
          TRUE
        ),
        updated_at = now()
    WHERE team_id = p_team_id;
  ELSE
    UPDATE public.pool_teams
    SET guest_profile = jsonb_set(
          COALESCE(guest_profile, '{}'::jsonb),
          '{bet_agreed}',
          to_jsonb(p_agreed),
          TRUE
        ),
        updated_at = now()
    WHERE team_id = p_team_id;
  END IF;

  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.settle_pool_team(
  p_team_id UUID,
  p_winner_index INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, auth
AS $$
DECLARE
  current_team public.pool_teams%ROWTYPE;
  winner UUID;
  loser UUID;
  winner_profile JSONB;
  loser_profile JSONB;
  winner_name TEXT;
  loser_bet INTEGER;
  winner_bonus INTEGER;
  app_share INTEGER;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_winner_index IS NULL OR p_winner_index NOT IN (0, 1) THEN
    RAISE EXCEPTION 'Invalid winner index';
  END IF;

  SELECT * INTO current_team
  FROM public.pool_teams
  WHERE team_id = p_team_id
  FOR UPDATE;

  IF NOT FOUND
     OR current_team.host_id <> auth.uid()
     OR current_team.status <> 'playing'
     OR current_team.settled_at IS NOT NULL
     OR current_team.guest_id IS NULL THEN
    RETURN FALSE;
  END IF;

  winner := CASE WHEN p_winner_index = 0
    THEN current_team.host_id ELSE current_team.guest_id END;
  loser := CASE WHEN p_winner_index = 0
    THEN current_team.guest_id ELSE current_team.host_id END;
  winner_profile := CASE WHEN p_winner_index = 0
    THEN current_team.host_profile ELSE current_team.guest_profile END;
  loser_profile := CASE WHEN p_winner_index = 0
    THEN current_team.guest_profile ELSE current_team.host_profile END;
  winner_name := COALESCE(
    winner_profile->>'username',
    winner_profile->>'full_name',
    winner::TEXT
  );
  loser_bet := COALESCE((loser_profile->>'bet')::INTEGER, 0);

  IF loser_bet > 0 THEN
    IF COALESCE((current_team.host_profile->>'bet_agreed')::BOOLEAN, FALSE) = FALSE
       OR COALESCE((current_team.guest_profile->>'bet_agreed')::BOOLEAN, FALSE) = FALSE THEN
      RAISE EXCEPTION 'Bet was not accepted by both players';
    END IF;

    UPDATE public.users
    SET coins = coins - loser_bet
    WHERE id = loser
      AND coins >= loser_bet;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Loser does not have enough coins to settle the bet';
    END IF;

    winner_bonus := (loser_bet * 2) / 3;
    app_share := loser_bet - winner_bonus;

    UPDATE public.users
    SET coins = coins + winner_bonus
    WHERE id = winner;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Winner profile was not found';
    END IF;

    IF app_share > 0 THEN
      INSERT INTO public.app_gains (
        match_code,
        amount,
        bet,
        winner_team,
        created_at
      )
      VALUES (
        'pool_' || p_team_id::TEXT,
        app_share,
        loser_bet,
        winner_name,
        now()
      );
    END IF;
  END IF;

  UPDATE public.pool_teams
  SET winner_id = winner,
      settled_at = now(),
      updated_at = now()
  WHERE team_id = p_team_id;

  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.cancel_pool_team(p_team_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  UPDATE public.pool_teams
  SET status = 'cancelled', updated_at = now()
  WHERE team_id = p_team_id
    AND host_id = auth.uid()
    AND status IN ('waiting', 'public_waiting', 'matched');

  RETURN FOUND;
END;
$$;

REVOKE ALL ON FUNCTION public.create_pool_team(JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_pool_team(UUID, JSONB, BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_pool_team_by_code(TEXT, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.try_match_pool_team(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.start_pool_team(UUID, BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_pool_team_bet(UUID, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_pool_team_bet_agreement(UUID, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.settle_pool_team(UUID, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.cancel_pool_team(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_pool_team(JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_pool_team(UUID, JSONB, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_pool_team_by_code(TEXT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.try_match_pool_team(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_pool_team(UUID, BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_pool_team_bet(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_pool_team_bet_agreement(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.settle_pool_team(UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_pool_team(UUID) TO authenticated;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'pool_teams'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.pool_teams;
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
