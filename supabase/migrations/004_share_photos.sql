-- Migración 004: Añadir campo share_photos a users
-- Permite que los usuarios elijan si sus fotos de vinilos aparecen en el feed social

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS share_photos boolean DEFAULT false;

COMMENT ON COLUMN public.users.share_photos IS 'Si true, las fotos de vinilos del usuario aparecen en el feed social';
