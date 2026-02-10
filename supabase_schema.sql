-- ===========================================
-- VINYL SCOUT - Schema de Base de Datos
-- ===========================================
-- Ejecutar en Supabase SQL Editor
-- ===========================================

-- 1. Habilitar extensión para búsqueda por IA (Embeddings)
create extension if not exists vector;

-- 2. Tabla de Usuarios (Espejo de fossil-scout con añadidos de Discogs)
create table public.users (
  id uuid not null default extensions.uuid_generate_v4(),
  google_id text not null,
  email text not null,
  display_name text not null,
  photo_url text null,
  discogs_access_token text null, 
  discogs_username text null,
  is_public boolean default false, -- Perfil público visible en feed
  share_photos boolean default false, -- Publicar fotos de vinilos en el feed
  username text, -- Username único para búsqueda
  bio text, -- Bio del perfil público
  created_at timestamp with time zone default now(),
  constraint users_pkey primary key (id),
  constraint users_email_key unique (email)
);

-- 3. Tabla de Estanterías (La "Foto Maestra")
create table public.shelves (
  id uuid primary key default extensions.uuid_generate_v4(),
  user_id uuid references public.users(id) on delete cascade not null,
  name text not null,
  master_photo_url text not null,
  is_public boolean default false, -- Visible en feed público
  created_at timestamp with time zone default now()
);

-- 4. Tabla de Zonas (Los "Huecos" de tu mueble)
create table public.shelf_zones (
  id uuid primary key default extensions.uuid_generate_v4(),
  shelf_id uuid references public.shelves(id) on delete cascade not null,
  zone_index int not null,
  detail_photo_url text,
  center_x float not null, -- Coordenada X relativa (0-1)
  center_y float not null, -- Coordenada Y relativa (0-1)
  last_scanned_at timestamp with time zone,
  created_at timestamp with time zone default now()
);

-- 5. Tabla de Álbumes (El inventario real)
create table public.albums (
  id uuid primary key default extensions.uuid_generate_v4(),
  user_id uuid references public.users(id) on delete cascade not null,
  zone_id uuid references public.shelf_zones(id) on delete set null,
  discogs_id bigint, 
  title text not null,
  artist text not null,
  cover_url text,
  year int,
  genres text[],
  styles text[],
  position_index int, -- Posición dentro del hueco (1, 2, 3...)
  embedding vector(1536), -- Para las recomendaciones de Gemini
  tracklist jsonb, -- [{position: "A1", title: "Song", duration: "3:45"}, ...]
  created_at timestamp with time zone default now(),
  last_played_at timestamp with time zone -- Para playlists inteligentes
);

-- 6. Playlists y Moods
create table public.playlists (
  id uuid primary key default extensions.uuid_generate_v4(),
  user_id uuid references public.users(id) on delete cascade not null,
  name text not null,
  is_mood_generated boolean default false,
  created_at timestamp with time zone default now()
);

create table public.playlist_items (
  playlist_id uuid references public.playlists(id) on delete cascade not null,
  album_id uuid references public.albums(id) on delete cascade not null,
  primary key (playlist_id, album_id)
);

-- 7. Historial de Escucha
create table public.play_history (
  id uuid primary key default extensions.uuid_generate_v4(),
  user_id uuid references public.users(id) on delete cascade not null,
  album_id uuid references public.albums(id) on delete cascade not null,
  played_at timestamp with time zone default now(),
  request_context text -- Contexto de la petición (mood, texto libre, etc.)
);

-- 8. Wishlist (discos deseados)
create table public.wishlist_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(id) on delete cascade not null,
  title text not null,
  artist text not null,
  cover_url text,
  year int,
  discogs_id bigint,
  note text,
  created_at timestamptz default now()
);

-- 9. Fotos de vinilos (subidas por el usuario)
create table public.album_photos (
  id uuid primary key default gen_random_uuid(),
  album_id uuid references public.albums(id) on delete cascade not null,
  user_id uuid references public.users(id) on delete cascade not null,
  photo_url text not null,
  caption text,
  created_at timestamptz default now()
);

-- 10. Tabla de Follows (unidireccional, tipo Instagram)
create table public.follows (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid references public.users(id) on delete cascade not null,
  following_id uuid references public.users(id) on delete cascade not null,
  created_at timestamptz default now(),
  unique(follower_id, following_id),
  check(follower_id != following_id)
);

-- ===========================================
-- ÍNDICES PARA OPTIMIZACIÓN
-- ===========================================

-- Índice para búsqueda de estanterías por usuario
create index idx_shelves_user_id on public.shelves(user_id);

-- Índice para búsqueda de zonas por estantería
create index idx_shelf_zones_shelf_id on public.shelf_zones(shelf_id);

-- Índice para búsqueda de álbumes por usuario y zona
create index idx_albums_user_id on public.albums(user_id);
create index idx_albums_zone_id on public.albums(zone_id);

-- Índice para búsqueda por discogs_id (sincronización)
create index idx_albums_discogs_id on public.albums(discogs_id);

-- Índice para historial de escucha por usuario y fecha
create index idx_play_history_user_id on public.play_history(user_id);
create index idx_play_history_played_at on public.play_history(played_at desc);

-- Índices para follows
create index idx_wishlist_user_id on public.wishlist_items(user_id);

create index idx_album_photos_album_id on public.album_photos(album_id);
create index idx_album_photos_user_id on public.album_photos(user_id);
create index idx_album_photos_created_at on public.album_photos(created_at desc);

create index idx_follows_follower on public.follows(follower_id);
create index idx_follows_following on public.follows(following_id);

-- Índice para username único (permite nulls)
create unique index idx_users_username on public.users(username) where username is not null;

-- Índice para feed de estanterías públicas
create index idx_shelves_public on public.shelves(is_public, created_at desc) where is_public = true;

-- ===========================================
-- ROW LEVEL SECURITY (RLS)
-- ===========================================

-- Habilitar RLS en todas las tablas
alter table public.users enable row level security;
alter table public.shelves enable row level security;
alter table public.shelf_zones enable row level security;
alter table public.albums enable row level security;
alter table public.playlists enable row level security;
alter table public.playlist_items enable row level security;
alter table public.play_history enable row level security;
-- Wishlist RLS
alter table public.wishlist_items enable row level security;

create policy "Users can manage their own wishlist"
  on public.wishlist_items for all
  using (auth.uid() = user_id);

create policy "Anyone can view wishlist of public users"
  on public.wishlist_items for select
  using (
    exists (
      select 1 from public.users
      where users.id = wishlist_items.user_id
      and users.is_public = true
    )
  );

-- Album photos RLS
alter table public.album_photos enable row level security;

create policy "Users can manage their own album photos"
  on public.album_photos for all
  using (auth.uid() = user_id);

create policy "Anyone can view photos of public users"
  on public.album_photos for select
  using (
    exists (
      select 1 from public.users
      where users.id = album_photos.user_id
      and users.is_public = true
    )
  );

alter table public.follows enable row level security;

-- Políticas para users
create policy "Users can view their own profile"
  on public.users for select
  using (auth.uid() = id);

create policy "Anyone can view public profiles"
  on public.users for select
  using (is_public = true);

create policy "Users can update their own profile"
  on public.users for update
  using (auth.uid() = id);

-- Políticas para shelves
create policy "Users can view their own shelves"
  on public.shelves for select
  using (auth.uid() = user_id);

create policy "Anyone can view public shelves"
  on public.shelves for select
  using (
    is_public = true
    and exists (
      select 1 from public.users
      where users.id = shelves.user_id
      and users.is_public = true
    )
  );

create policy "Users can create their own shelves"
  on public.shelves for insert
  with check (auth.uid() = user_id);

create policy "Users can update their own shelves"
  on public.shelves for update
  using (auth.uid() = user_id);

create policy "Users can delete their own shelves"
  on public.shelves for delete
  using (auth.uid() = user_id);

-- Políticas para shelf_zones
create policy "Users can view zones of their shelves"
  on public.shelf_zones for select
  using (
    exists (
      select 1 from public.shelves
      where shelves.id = shelf_zones.shelf_id
      and shelves.user_id = auth.uid()
    )
  );

create policy "Users can manage zones of their shelves"
  on public.shelf_zones for all
  using (
    exists (
      select 1 from public.shelves
      where shelves.id = shelf_zones.shelf_id
      and shelves.user_id = auth.uid()
    )
  );

-- Políticas para albums
create policy "Users can view their own albums"
  on public.albums for select
  using (auth.uid() = user_id);

create policy "Anyone can view albums of public users"
  on public.albums for select
  using (
    exists (
      select 1 from public.users
      where users.id = albums.user_id
      and users.is_public = true
    )
  );

create policy "Users can manage their own albums"
  on public.albums for all
  using (auth.uid() = user_id);

-- Políticas para playlists
create policy "Users can view their own playlists"
  on public.playlists for select
  using (auth.uid() = user_id);

create policy "Users can manage their own playlists"
  on public.playlists for all
  using (auth.uid() = user_id);

-- Políticas para play_history
create policy "Users can view their own play history"
  on public.play_history for select
  using (auth.uid() = user_id);

create policy "Users can manage their own play history"
  on public.play_history for all
  using (auth.uid() = user_id);

-- Políticas para playlist_items
create policy "Users can manage items in their playlists"
  on public.playlist_items for all
  using (
    exists (
      select 1 from public.playlists
      where playlists.id = playlist_items.playlist_id
      and playlists.user_id = auth.uid()
    )
  );

-- Políticas para follows
create policy "Anyone can view follows"
  on public.follows for select
  using (auth.role() = 'authenticated');

create policy "Users can follow others"
  on public.follows for insert
  with check (auth.uid() = follower_id);

create policy "Users can unfollow"
  on public.follows for delete
  using (auth.uid() = follower_id);

-- Política para zonas públicas
create policy "Anyone can view zones of public shelves"
  on public.shelf_zones for select
  using (
    exists (
      select 1 from public.shelves
      where shelves.id = shelf_zones.shelf_id
      and shelves.is_public = true
      and exists (
        select 1 from public.users
        where users.id = shelves.user_id
        and users.is_public = true
      )
    )
  );
