-- ===========================================
-- MIGRACIÓN: Wishlist (Fase 2)
-- ===========================================
-- Ejecutar en Supabase SQL Editor
-- ===========================================

-- 1. Tabla de wishlist
CREATE TABLE IF NOT EXISTS public.wishlist_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  title text NOT NULL,
  artist text NOT NULL,
  cover_url text,
  year int,
  discogs_id bigint,
  note text, -- "Me lo recomendó Diego"
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_wishlist_user_id ON public.wishlist_items(user_id);

-- 2. RLS
ALTER TABLE public.wishlist_items ENABLE ROW LEVEL SECURITY;

-- Propietario puede hacer CRUD
CREATE POLICY "Users can manage their own wishlist"
  ON public.wishlist_items FOR ALL
  USING (auth.uid() = user_id);

-- Cualquiera puede ver wishlist de usuarios públicos
CREATE POLICY "Anyone can view wishlist of public users"
  ON public.wishlist_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = wishlist_items.user_id
      AND users.is_public = true
    )
  );
