CREATE TABLE public.feedbacks (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  category TEXT NOT NULL CHECK (category IN ('suggestion', 'bug', 'feature', 'other')),
  message TEXT NOT NULL,
  contact_email TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.feedbacks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert feedback"
  ON public.feedbacks FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Admins can read all feedback"
  ON public.feedbacks FOR SELECT
  USING (auth.uid() IN (
    SELECT id FROM public.users WHERE email = 'contact@smartdev-solutions.com'
  ));
