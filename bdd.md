-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.teams (
  team_id text NOT NULL,
  host_id text NOT NULL,
  host_profile jsonb DEFAULT '{}'::jsonb,
  guest_id text,
  guest_profile jsonb DEFAULT '{}'::jsonb,
  guest_ready boolean DEFAULT false,
  status text DEFAULT 'waiting'::text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT teams_pkey PRIMARY KEY (team_id)
);
CREATE TABLE public.users (
  id uuid NOT NULL,
  email text NOT NULL UNIQUE,
  full_name text,
  avatar_url text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  username text UNIQUE,
  coins integer NOT NULL DEFAULT 0,
  is_connected boolean NOT NULL DEFAULT false,
  CONSTRAINT users_pkey PRIMARY KEY (id),
  CONSTRAINT users_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);
CREATE TABLE public.amis (
  id_ami uuid NOT NULL,
  id_user uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT amis_pkey PRIMARY KEY (id_ami, id_user),
  CONSTRAINT amis_id_ami_fkey FOREIGN KEY (id_ami) REFERENCES public.users(id),
  CONSTRAINT amis_id_user_fkey FOREIGN KEY (id_user) REFERENCES public.users(id)
);
CREATE TABLE public.games (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  image_url text,
  name text NOT NULL,
  nbr_players integer NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT games_pkey PRIMARY KEY (id)
);
CREATE TABLE public.player_games (
  game_id uuid NOT NULL,
  player_id uuid NOT NULL,
  score integer DEFAULT 0,
  nbr_wins integer DEFAULT 0,
  nbr_losses integer DEFAULT 0,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT player_games_pkey PRIMARY KEY (game_id, player_id),
  CONSTRAINT player_games_game_id_fkey FOREIGN KEY (game_id) REFERENCES public.games(id),
  CONSTRAINT player_games_player_id_fkey FOREIGN KEY (player_id) REFERENCES public.users(id)
);