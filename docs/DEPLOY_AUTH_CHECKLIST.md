# Checklist: Configuración de Login OAuth para VinylScout (Producción)

## Problema
Al hacer login en producción, la app redirige a `localhost:56841` (o 5687, 3000) en lugar de la URL de GitHub Pages.

## Causa probable
Supabase usa la **Site URL** como redirección por defecto cuando:
1. La URL de `redirectTo` no está en la lista de Redirect URLs permitidas, o
2. Hay algún error en la validación.

Si la Site URL en Supabase está configurada como `http://localhost:56841` (puerto por defecto de `flutter run -d chrome`) o `http://localhost:5687`, eso explica el comportamiento.

---

## 1. Supabase Dashboard – URL Configuration

**Ruta:** [Supabase Dashboard](https://supabase.com/dashboard) → Proyecto de VinylScout → **Authentication** → **URL Configuration**

### 1.1 Site URL
- **Debe ser:** `https://<tu-usuario>.github.io/vinyl-scout/`
  - Ejemplo: `https://dbaez.github.io/vinyl-scout/`
- **No debe ser:** `http://localhost:5687` ni `http://localhost:3000`

### 1.2 Redirect URLs (lista de URLs permitidas)
Añade exactamente:

```
https://<tu-usuario>.github.io/vinyl-scout/
https://<tu-usuario>.github.io/vinyl-scout/**
```

Para desarrollo local (opcional):

```
http://localhost:3000/
http://localhost:3000/**
http://localhost:5687/
http://localhost:5687/**
```

---

## 2. Google Cloud Console – OAuth

**Ruta:** [Google Cloud Console](https://console.cloud.google.com) → APIs & Services → Credentials

En el OAuth 2.0 Client ID (tipo Web application), en **Authorized redirect URIs** debe estar:

```
https://<tu-project-ref>.supabase.co/auth/v1/callback
```

(Obtén el project-ref desde la URL de tu proyecto Supabase.)

---

## 3. GitHub – Secrets y Pages

**Ruta:** Repositorio vinyl-scout → Settings → Secrets and variables → Actions

### 3.1 Secrets obligatorios
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `DISCOGS_TOKEN` (o DISCOGS_CONSUMER_KEY + DISCOGS_CONSUMER_SECRET si los usas)
- `GEMINI_API_KEY`

### 3.2 Secret opcional: PAGES_REDIRECT_URL
Si quieres una URL distinta a la por defecto, define:
- `PAGES_REDIRECT_URL` = `https://<usuario>.github.io/vinyl-scout/`

Si no lo defines, el workflow usa `https://<repository_owner>.github.io/vinyl-scout/` automáticamente.

---

## 4. Flujo del código (VinylScout)

En `lib/main.dart`, la lógica de redirect es:

1. **Producción (build con APP_REDIRECT_URL):** usa `EnvConfig.appRedirectUrl` (inyectada en el build).
2. **Desarrollo local (APP_REDIRECT_URL vacía):** usa `Uri.base.origin` + path.

El workflow `deploy-web.yml` inyecta `APP_REDIRECT_URL` en el build. Si los secrets están bien, la URL de producción se usa correctamente.

**El fallo suele estar en Supabase:** aunque el código pase la URL correcta en `redirectTo`, si esa URL no está en la lista de Redirect URLs de Supabase, Supabase ignora el parámetro y redirige a la Site URL (que puede ser localhost:5687).

---

## 5. Pasos recomendados (orden)

1. **Supabase** (lo más importante):
   - Authentication → URL Configuration
   - Site URL: `https://<usuario>.github.io/vinyl-scout/`
   - Redirect URLs: añadir `https://<usuario>.github.io/vinyl-scout/` y `https://<usuario>.github.io/vinyl-scout/**`
   - Guardar

2. **Google Cloud:** verificar que el redirect URI de Supabase está en Authorized redirect URIs.

3. **GitHub:** verificar que los secrets existen y que el deploy de Pages funciona.

4. **Probar:** hacer login en la URL de producción y comprobar que la redirección va a GitHub Pages y no a localhost.

---

## Referencias

- [Supabase Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)
- [Supabase: Redirect to wrong URL](https://supabase.com/docs/guides/troubleshooting/why-am-i-being-redirected-to-the-wrong-url-when-using-auth-redirectto-option-_vqIeO)
