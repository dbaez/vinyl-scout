#!/bin/bash
# ===========================================
# VinylScout - Script de desarrollo
# ===========================================
# Carga variables de .env y ejecuta Flutter
# Uso: ./run_dev.sh [chrome|ios|android|macos]
# ===========================================

# Cargar variables del archivo .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | grep -v '^$' | xargs)
else
    echo "❌ Error: No se encontró el archivo .env"
    echo "   Copia .env.example a .env y configura tus credenciales"
    exit 1
fi

# Verificar variables obligatorias
if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
    echo "❌ Error: Faltan SUPABASE_URL o SUPABASE_ANON_KEY en .env"
    exit 1
fi

# Dispositivo por defecto
DEVICE=${1:-chrome}

echo "🚀 Iniciando VinylScout en: $DEVICE"
echo "📦 Supabase URL: ${SUPABASE_URL:0:30}..."

# Argumentos extra para web (puerto fijo para OAuth redirect)
WEB_ARGS=""
if [ "$DEVICE" = "chrome" ] || [ "$DEVICE" = "web-server" ]; then
    WEB_ARGS="--web-port=3000"
fi

# Ejecutar Flutter con las variables de entorno
flutter run -d "$DEVICE" $WEB_ARGS \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
    --dart-define=DISCOGS_CONSUMER_KEY="${DISCOGS_CONSUMER_KEY:-}" \
    --dart-define=DISCOGS_CONSUMER_SECRET="${DISCOGS_CONSUMER_SECRET:-}" \
    --dart-define=GEMINI_API_KEY="${GEMINI_API_KEY:-}"
