-- ===========================================
-- MIGRACIÓN: Fotos de Vinilos (Fase 3)
-- ===========================================
-- Ejecutar en Supabase SQL Editor
-- ===========================================

-- 1. Tabla de fotos de álbumes
CREATE TABLE IF NOT EXISTS public.album_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  album_id uuid REFERENCES public.albums(id) ON DELETE CASCADE NOT NULL,
  user_id uuid REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  photo_url text NOT NULL,
  caption text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_album_photos_album_id ON public.album_photos(album_id);
CREATE INDEX IF NOT EXISTS idx_album_photos_user_id ON public.album_photos(user_id);
CREATE INDEX IF NOT EXISTS idx_album_photos_created_at ON public.album_photos(created_at DESC);

-- 2. RLS
ALTER TABLE public.album_photos ENABLE ROW LEVEL SECURITY;

-- Propietario puede hacer CRUD
CREATE POLICY "Users can manage their own album photos"
  ON public.album_photos FOR ALL
  USING (auth.uid() = user_id);

-- Cualquiera puede ver fotos de usuarios públicos
CREATE POLICY "Anyone can view photos of public users"
  ON public.album_photos FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = album_photos.user_id
      AND users.is_public = true
    )
  );

-- 3. Bucket vinyl-photos (crear manualmente en Supabase Dashboard > Storage)
-- Configuración recomendada:
--   - Public bucket: true (para URLs públicas)
--   - File size limit: 5MB
--   - Allowed MIME types: image/jpeg, image/png, image/webp
