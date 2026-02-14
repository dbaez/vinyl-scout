# Soluciones recomendadas por Google para el login (disallowed_useragent)

Google recomienda estas prácticas para evitar el error 403 disallowed_useragent. Este documento explica cómo aplicarlas a VinylScout.

---

## Contexto: Custom Tabs / SFSafariViewController

**Custom Tabs (Android)** y **SFSafariViewController (iOS)** son para **apps nativas** (Android/iOS). VinylScout es una **app web** (Flutter Web en GitHub Pages), así que estas herramientas no aplican directamente.

El equivalente en web es usar las soluciones que Google recomienda para la plataforma web.

---

## Opción 1: Google Identity Services + signInWithIdToken (recomendada)

Es la solución que **Google y Supabase recomiendan** para web. Evita el redirect OAuth y no depende del User-Agent del navegador.

### Cómo funciona

1. Se carga el SDK de **Google Identity Services** (GIS) en la página.
2. Se muestra el botón "Sign in with Google" o One Tap.
3. El usuario hace clic y GIS obtiene el **ID token** (sin redirect completo).
4. Se pasa el token a Supabase: `signInWithIdToken(provider: 'google', token: credential)`.
5. Supabase valida el token y crea la sesión.

### Ventajas

- No hay redirect a Google → no hay error disallowed_useragent.
- Funciona en PWA, WebView e in-app browsers.
- Es la vía oficial recomendada por Google.
- Compatible con Supabase.

### Implementación en Flutter Web

Requiere integrar el SDK de GIS (JavaScript) con Flutter. Opciones:

1. **google_identity_services_web** – paquete Dart para GIS.
2. **HtmlElementView** – incrustar el botón HTML de Google en Flutter.
3. **dart:js_interop** – llamar directamente a la API de GIS desde Dart.

### Pasos básicos

1. Añadir el script en `web/index.html`:
   ```html
   <script src="https://accounts.google.com/gsi/client" async defer></script>
   ```

2. Configurar el botón/callback en JavaScript o vía interop.

3. En el callback, llamar a Supabase desde Dart:
   ```dart
   await Supabase.instance.client.auth.signInWithIdToken(
     provider: OAuthProvider.google,
     idToken: credential, // token del callback de GIS
   );
   ```

4. En Supabase Dashboard → Authentication → Providers → Google: tener configurado Client ID y Client Secret.

---

## Opción 2: Nueva pestaña (implementada actualmente)

La solución actual abre el OAuth en una **nueva pestaña** (`_blank`). La nueva pestaña usa el navegador completo, no un WebView, así que el User-Agent es válido.

### Ventajas

- Implementación sencilla.
- Funciona en la mayoría de casos (PWA, enlaces desde redes sociales, etc.).

### Limitaciones

- El usuario termina en otra pestaña tras el login.
- Puede haber bloqueo de popups en algunos navegadores.

---

## Opción 3: Librerías oficiales (AppAuth, etc.)

**AppAuth** está pensada sobre todo para apps nativas. Para web, la opción recomendada es **Google Identity Services** (opción 1).

---

## No hacer: modificar el User-Agent

Google desaconseja cambiar el User-Agent por código. Suele fallar o provocar bloqueos adicionales.

---

## Resumen

| Solución                         | Complejidad | Compatibilidad | Recomendación Google |
|---------------------------------|-------------|----------------|----------------------|
| GIS + signInWithIdToken         | Media       | Alta           | Sí                   |
| Nueva pestaña (actual)          | Baja        | Media-alta     | No explícita         |
| signInWithOAuth (redirect)      | Baja        | Baja en WebView| No                   |

---

## Próximos pasos sugeridos

1. Mantener la solución actual (nueva pestaña) como medida inmediata.
2. Planear la migración a **Google Identity Services + signInWithIdToken** como solución a largo plazo.
3. Revisar el paquete `google_identity_services_web` o la integración vía `dart:js_interop` para Flutter Web.

---

## Referencias

- [Supabase: Login with Google](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Google Identity Services - Web](https://developers.google.com/identity/gsi/web/guides/overview)
- [Supabase signInWithIdToken](https://supabase.com/docs/reference/dart/auth-signinwithidtoken)
