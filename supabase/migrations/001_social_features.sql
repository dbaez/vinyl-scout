-- ===========================================
-- MIGRACIÓN: Funcionalidades Sociales (Fase 1)
-- ===========================================
-- Ejecutar en Supabase SQL Editor
-- ===========================================

-- 1. Nuevas columnas en users
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_public boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS username text,
  ADD COLUMN IF NOT EXISTS bio text;

-- Índice único para username (permite nulls)
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON public.users(username) WHERE username IS NOT NULL;

-- 2. Nueva columna en shelves
ALTER TABLE public.shelves
  ADD COLUMN IF NOT EXISTS is_public boolean DEFAULT false;

-- 3. Tabla de follows (unidireccional, tipo Instagram)
CREATE TABLE IF NOT EXISTS public.follows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id uuid REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  following_id uuid REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE(follower_id, following_id),
  CHECK(follower_id != following_id) -- No puedes seguirte a ti mismo
);

CREATE INDEX IF NOT EXISTS idx_follows_follower ON public.follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON public.follows(following_id);

-- 4. Índice para feed: estanterías públicas ordenadas por fecha
CREATE INDEX IF NOT EXISTS idx_shelves_public ON public.shelves(is_public, created_at DESC) WHERE is_public = true;

-- ===========================================
-- RLS para follows
-- ===========================================
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

-- Cualquiera autenticado puede ver follows (necesario para contadores)
CREATE POLICY "Anyone can view follows"
  ON public.follows FOR SELECT
  USING (auth.role() = 'authenticated');

-- Solo puedes crear follows donde tú eres el follower
CREATE POLICY "Users can follow others"
  ON public.follows FOR INSERT
  WITH CHECK (auth.uid() = follower_id);

-- Solo puedes eliminar tus propios follows
CREATE POLICY "Users can unfollow"
  ON public.follows FOR DELETE
  USING (auth.uid() = follower_id);

-- ===========================================
-- NUEVAS POLÍTICAS: acceso público a perfiles/colecciones
-- ===========================================

-- Users: cualquiera puede ver perfiles públicos
CREATE POLICY "Anyone can view public profiles"
  ON public.users FOR SELECT
  USING (is_public = true);

-- Shelves: cualquiera puede ver estanterías públicas de usuarios públicos
CREATE POLICY "Anyone can view public shelves"
  ON public.shelves FOR SELECT
  USING (
    is_public = true
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = shelves.user_id
      AND users.is_public = true
    )
  );

-- Albums: cualquiera puede ver álbumes de usuarios públicos
CREATE POLICY "Anyone can view albums of public users"
  ON public.albums FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = albums.user_id
      AND users.is_public = true
    )
  );

-- Shelf zones: cualquiera puede ver zonas de estanterías públicas
CREATE POLICY "Anyone can view zones of public shelves"
  ON public.shelf_zones FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.shelves
      WHERE shelves.id = shelf_zones.shelf_id
      AND shelves.is_public = true
      AND EXISTS (
        SELECT 1 FROM public.users
        WHERE users.id = shelves.user_id
        AND users.is_public = true
      )
    )
  );
