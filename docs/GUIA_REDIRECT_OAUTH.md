# Guía paso a paso: Arreglar redirect a localhost en login con Google (GitHub Pages)

**Tu URL de producción:** `https://dbaez.github.io/vinyl-scout/`

Cuando haces login con Google en producción y te redirige a `localhost`, el problema está en la configuración de OAuth. Sigue estos pasos en orden.

---

## Paso 1: Supabase Dashboard

### 1.1 Acceder a URL Configuration

1. Entra en [Supabase Dashboard](https://supabase.com/dashboard)
2. Selecciona tu proyecto **VinylScout**
3. En el menú lateral: **Authentication** → **URL Configuration**

### 1.2 Site URL (crítico)

**Qué ver:** Campo "Site URL"

**Debe estar así:**
```
https://dbaez.github.io/vinyl-scout/
```

**NO debe estar:**
- `http://localhost:56841` ← **Puerto típico de Flutter web** (el que suele causar el problema)
- `http://localhost:5687`
- `http://localhost:3000`
- Cualquier URL con `localhost` o puertos efímeros (56841, 56842, etc.)

Si está en localhost, cámbialo a la URL de producción y guarda.

### 1.3 Redirect URLs (lista de URLs permitidas)

**Qué ver:** Campo "Redirect URLs" (lista, una por línea)

**Debe incluir exactamente estas líneas:**
```
https://dbaez.github.io/vinyl-scout/
https://dbaez.github.io/vinyl-scout/**
```

Opcional para desarrollo local:
```
http://localhost:3000/
http://localhost:3000/**
http://localhost:5687/
http://localhost:5687/**
http://localhost:56841/
http://localhost:56841/**
```
(56841 es el puerto que usa `flutter run -d chrome` por defecto)

**Importante:** Si la URL de producción NO está en esta lista, Supabase ignora el `redirectTo` que envía tu app y usa la Site URL. Si la Site URL es localhost, por eso te redirige ahí.

### 1.4 Guardar

Haz clic en **Save** al final de la sección URL Configuration.

---

## Paso 2: Google Cloud Console (GCP)

### 2.1 Acceder a Credentials

1. Entra en [Google Cloud Console](https://console.cloud.google.com)
2. Selecciona el proyecto donde configuraste OAuth para VinylScout
3. Menú: **APIs & Services** → **Credentials**

### 2.2 OAuth 2.0 Client ID

1. Busca el **OAuth 2.0 Client ID** de tipo **Web application** (el que usa Supabase para Google)
2. Haz clic para editarlo

### 2.3 Authorized redirect URIs

**Qué ver:** Sección "Authorized redirect URIs"

**Debe incluir exactamente:**
```
https://<TU-PROJECT-REF>.supabase.co/auth/v1/callback
```

Donde `<TU-PROJECT-REF>` es el identificador de tu proyecto Supabase.

**Cómo obtener el project-ref:**
- En Supabase Dashboard, la URL de tu proyecto es algo como: `https://supabase.com/dashboard/project/abcdefghijklmnop`
- O tu `SUPABASE_URL` es: `https://abcdefghijklmnop.supabase.co`
- El project-ref es la parte antes de `.supabase.co` (ej: `abcdefghijklmnop`)

**Ejemplo:**
```
https://xyzabc123.supabase.co/auth/v1/callback
```

**Importante:** Este URI es el de Supabase, NO el de tu app. Google redirige primero a Supabase, y Supabase luego redirige a tu app (usando la Site URL o la URL de la lista Redirect URLs).

### 2.4 Guardar

Haz clic en **Save** en el OAuth client.

---

## Paso 3: GitHub – Secrets y Actions

### 3.1 Acceder a Secrets

1. Repositorio: `https://github.com/dbaez/vinyl-scout`
2. **Settings** → **Secrets and variables** → **Actions**

### 3.2 Secrets obligatorios

Verifica que existan:

| Secret           | Descripción                                      |
|------------------|--------------------------------------------------|
| `SUPABASE_URL`   | URL de tu proyecto (ej: `https://xxx.supabase.co`) |
| `SUPABASE_ANON_KEY` | Clave anónima de Supabase                    |
| `DISCOGS_TOKEN`  | Token de Discogs (o DISCOGS_CONSUMER_KEY/SECRET)  |
| `GEMINI_API_KEY` | API key de Google Gemini                         |

### 3.3 Secret opcional: PAGES_REDIRECT_URL

Si tu URL de Pages es la estándar (`https://dbaez.github.io/vinyl-scout/`), **no hace falta** definirlo. El workflow la genera automáticamente.

Si usas un dominio personalizado o una URL distinta, define:
```
PAGES_REDIRECT_URL = https://dbaez.github.io/vinyl-scout/
```

### 3.4 Verificar el último deploy

1. Ve a la pestaña **Actions**
2. Abre el último workflow "Deploy to GitHub Pages"
3. Comprueba que el job **build-and-deploy** terminó en verde
4. En el step "Set redirect URL", la URL usada debería ser `https://dbaez.github.io/vinyl-scout/`

---

## Paso 4: Comprobar que el build usa la URL correcta

El workflow inyecta `APP_REDIRECT_URL` en el build. Si todo está bien:

- `PAGES_REDIRECT_URL` (si existe) o
- `https://dbaez.github.io/vinyl-scout/` (por defecto)

se pasa como `--dart-define=APP_REDIRECT_URL=...` al compilar.

Tu app en producción usa esa URL en `signInWithOAuth(redirectTo: ...)`. Si Supabase tiene esa URL en Redirect URLs y la Site URL es la de producción, el flujo debería funcionar.

---

## Resumen del flujo OAuth

1. Usuario hace clic en "Login con Google" en `https://dbaez.github.io/vinyl-scout/`
2. La app llama a `signInWithOAuth(redirectTo: 'https://dbaez.github.io/vinyl-scout/')`
3. Supabase redirige a Google
4. Google autentica y redirige a `https://xxx.supabase.co/auth/v1/callback`
5. Supabase valida y redirige al usuario a la URL de `redirectTo` **solo si** está en la lista de Redirect URLs
6. Si no está en la lista → Supabase usa la **Site URL** → si es localhost, ahí está el fallo

---

## Checklist rápido

- [ ] **Supabase:** Site URL = `https://dbaez.github.io/vinyl-scout/`
- [ ] **Supabase:** Redirect URLs incluye `https://dbaez.github.io/vinyl-scout/` y `https://dbaez.github.io/vinyl-scout/**`
- [ ] **GCP:** Authorized redirect URIs incluye `https://<project-ref>.supabase.co/auth/v1/callback`
- [ ] **GitHub:** Secrets `SUPABASE_URL` y `SUPABASE_ANON_KEY` configurados
- [ ] **GitHub:** Último deploy completado correctamente

---

## Error 403: disallowed_useragent (PWA / WebView)

Si los usuarios ven "Acceso bloqueado: la solicitud no cumple las políticas de Google sobre navegadores seguros":

**Causa:** Google bloquea OAuth cuando la app corre en WebView o PWA (ej. "Añadir a inicio" en móvil).

**Solución aplicada:** La app abre el login de Google en una **nueva pestaña** (`_blank`), donde el navegador tiene un user agent válido. Tras autenticarse, el usuario vuelve a la app en esa pestaña ya logueado.

---

## Si sigue fallando

1. **Limpia caché del navegador** o prueba en ventana de incógnito
2. **Revisa la consola del navegador** (F12) en la página de producción para ver si hay errores
3. **Comprueba en Supabase** → Authentication → Logs que el intento de login aparece y si hay errores
4. **Verifica** que no haya un proxy o extensión que modifique las URLs
