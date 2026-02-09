// Supabase Edge Function: process-vinyls
// Analiza una imagen de vinilos usando Google Gemini AI
// 
// Para desplegar:
// 1. Instala Supabase CLI: npm install -g supabase
// 2. Inicia sesión: supabase login
// 3. Link proyecto: supabase link --project-ref YOUR_PROJECT_REF
// 4. Configura secret: supabase secrets set GEMINI_API_KEY=tu_api_key
// 5. Despliega: supabase functions deploy process-vinyls --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
// Modelos con fallback (plan de pago activo)
const GEMINI_MODELS = [
  "gemini-2.0-flash",         // Primario: rápido y fiable, sin thinking
  "gemini-3-flash-preview",   // Fallback: más inteligente (thinking=minimal)
];
const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

// Timeout: 25s por modelo, guardia total 55s → ambos modelos tienen oportunidad
const GEMINI_TIMEOUT_MS = 25_000;
const TOTAL_GUARD_MS = 55_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface Album {
  position: number;
  artist: string;
  title: string;
  year?: number;
  confidence?: number;
  spine_x_start?: number;
  spine_x_end?: number;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { imageUrl, reanalyzePositions, spineCoords } = await req.json();

    if (!imageUrl) {
      throw new Error("imageUrl es requerido");
    }

    if (!GEMINI_API_KEY) {
      throw new Error("GEMINI_API_KEY no configurada");
    }

    const fnStart = Date.now();
    console.log("Procesando imagen:", imageUrl);

    // Descargar la imagen directamente (ya viene comprimida desde el cliente Flutter)
    const imageResponse = await fetch(imageUrl);
    if (!imageResponse.ok) {
      throw new Error(`Error descargando imagen: ${imageResponse.status}`);
    }
    
    const imageBuffer = await imageResponse.arrayBuffer();
    const mimeType = imageResponse.headers.get("content-type") || "image/jpeg";
    const sizeKB = (imageBuffer.byteLength / 1024).toFixed(1);
    console.log(`Imagen: ${sizeKB} KB (${mimeType}) descargada en ${Date.now() - fnStart}ms`);
    
    // Convertir a base64 en chunks (evita stack overflow con imágenes grandes)
    const uint8Array = new Uint8Array(imageBuffer);
    let binaryString = '';
    const chunkSize = 8192;
    for (let i = 0; i < uint8Array.length; i += chunkSize) {
      const chunk = uint8Array.slice(i, i + chunkSize);
      binaryString += String.fromCharCode.apply(null, Array.from(chunk));
    }
    const base64Image = btoa(binaryString);

    // Elegir prompt según modo
    const isReanalyze = reanalyzePositions && Array.isArray(reanalyzePositions) && reanalyzePositions.length > 0;
    let prompt: string;
    
    if (isReanalyze && spineCoords) {
      const zonesDesc = reanalyzePositions.map((pos: number) => {
        const coord = spineCoords[pos];
        if (coord) {
          return `- #${pos}: zona ${(coord.xStart * 100).toFixed(0)}%-${(coord.xEnd * 100).toFixed(0)}% horizontal`;
        }
        return `- #${pos}`;
      }).join("\n");

      prompt = `Identifica estos vinilos específicos en la estantería. Enfócate en estas zonas:

${zonesDesc}

Lee el texto de cada lomo con detalle. Si no puedes leerlo, pon "Unknown Artist"/"Unknown Album" con confianza baja.

Responde SOLO JSON:
{"albums":[{"position":5,"artist":"Artista","title":"Álbum","year":2020,"confidence":0.7}]}`;
    } else {
      // Prompt optimizado: más corto = menos tokens = respuesta más rápida
      prompt = `Identifica los vinilos en esta estantería leyendo los lomos de IZQUIERDA a DERECHA.

REGLAS:
- 1 lomo físico = 1 entrada. NO inventes discos que no ves.
- NO completes discografías. Lee CADA lomo por separado.
- Si no puedes leer un lomo: "Unknown Artist"/"Unknown Album", confidence 0.1.
- Confianza: 0.95+ texto claro, 0.7-0.94 parcial, 0.3-0.69 visual, 0.1-0.29 ilegible.

Responde SOLO JSON válido (sin markdown):
{"albums":[{"position":1,"artist":"Nombre","title":"Título","year":2020,"confidence":0.9,"spine_x_start":0.0,"spine_x_end":0.03}]}`;
    }
    
    console.log(`Modo: ${isReanalyze ? 'RE-ANÁLISIS' : 'COMPLETO'} | Prompt: ${prompt.length} chars`);

    // Llamar a Gemini con fallback entre modelos
    // Preparar request body por modelo (cada serie necesita config distinta para thinking)
    function buildRequestBody(model: string): string {
      const config: Record<string, unknown> = {
        temperature: 0.1,
        maxOutputTokens: 32768,
      };
      // Gemini 3: usar thinkingLevel "minimal" (thinkingBudget NO funciona bien)
      if (model.includes("gemini-3")) {
        config.thinkingConfig = { thinkingLevel: "minimal" };
      }
      // Gemini 2.5: usar thinkingBudget 0 para desactivar thinking
      else if (model.includes("gemini-2.5")) {
        config.thinkingConfig = { thinkingBudget: 0 };
      }
      // Gemini 2.0: no soporta thinking, no incluir thinkingConfig
      return JSON.stringify({
        contents: [{
          parts: [
            { text: prompt },
            { inline_data: { mime_type: mimeType, data: base64Image } },
          ],
        }],
        generationConfig: config,
      });
    }

    let geminiResponse: Response | null = null;
    let usedModel = "";
    let lastError = "";

    for (const model of GEMINI_MODELS) {
      const elapsed = Date.now() - fnStart;
      // Guardia: si ya llevamos >55s total, no intentar más modelos
      if (elapsed > TOTAL_GUARD_MS) {
        console.warn(`Tiempo total ${elapsed}ms, abortando fallback`);
        break;
      }
      
      const url = `${GEMINI_BASE}/${model}:generateContent?key=${GEMINI_API_KEY}`;
      const modelStart = Date.now();
      console.log(`→ ${model} (total elapsed: ${elapsed}ms, timeout: ${GEMINI_TIMEOUT_MS}ms)`);
      
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), GEMINI_TIMEOUT_MS);
      
      try {
        const resp = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: buildRequestBody(model),
          signal: controller.signal,
        });
        clearTimeout(timeoutId);

        if (resp.ok) {
          geminiResponse = resp;
          usedModel = model;
          console.log(`✓ ${model} OK en ${(Date.now() - modelStart)}ms (total: ${(Date.now() - fnStart)}ms)`);
          break;
        }

        const errorText = await resp.text();
        lastError = `${model}:${resp.status}`;
        console.warn(`✗ ${model} (${resp.status}): ${errorText.substring(0, 200)}`);
        
        if ([429, 500, 503].includes(resp.status)) continue;
        throw new Error(`Gemini ${resp.status}: ${errorText.substring(0, 200)}`);
      } catch (fetchError) {
        clearTimeout(timeoutId);
        if (fetchError instanceof Error && fetchError.message.startsWith("Gemini ")) throw fetchError;
        
        if (fetchError instanceof DOMException && fetchError.name === "AbortError") {
          lastError = `${model}: timeout ${GEMINI_TIMEOUT_MS / 1000}s`;
          console.warn(`✗ ${model} TIMEOUT (${GEMINI_TIMEOUT_MS / 1000}s) — intentando siguiente modelo...`);
          continue; // Timeout = probar el siguiente modelo
        }
        lastError = `${model}: ${fetchError}`;
        console.warn(`✗ ${model} error:`, fetchError);
        continue;
      }
    }

    if (!geminiResponse) {
      throw new Error(`Modelos agotados. ${lastError}. Recorta la foto o inténtalo de nuevo.`);
    }

    const processingTime = (Date.now() - fnStart) / 1000;
    const geminiData = await geminiResponse.json();
    const finishReason = geminiData.candidates?.[0]?.finishReason ?? "UNKNOWN";
    console.log(`Finish: ${finishReason} | Total: ${processingTime}s`);

    const responseText = geminiData.candidates?.[0]?.content?.parts?.[0]?.text;
    
    if (!responseText) {
      const debugInfo = JSON.stringify(geminiData).substring(0, 2000);
      console.error("Respuesta vacía:", debugInfo);
      return new Response(JSON.stringify({
        albums: [], processingTime, model: usedModel, imageUrl,
        _debug: { error: "empty_response", finishReason, rawData: debugInfo },
      }), { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 });
    }

    console.log("Respuesta:", responseText.substring(0, 400));

    // Parsear JSON — limpiar markdown wrappers
    let jsonText = responseText.trim();
    const jsonMatch = jsonText.match(/```json\s*([\s\S]*?)\s*```/);
    if (jsonMatch) {
      jsonText = jsonMatch[1];
    } else {
      if (jsonText.startsWith("```json")) jsonText = jsonText.replace(/^```json\s*/, "");
      else if (jsonText.startsWith("```")) jsonText = jsonText.replace(/^```\s*/, "");
      jsonText = jsonText.replace(/\s*```\s*$/, "");
    }

    let albums: Album[] = [];
    let parseError: string | null = null;
    
    try {
      const parsed = JSON.parse(jsonText.trim());
      albums = Array.isArray(parsed) ? parsed : (parsed.albums || []);
    } catch (e) {
      console.warn("JSON parse falló, recuperando...");
      parseError = `${e}`;
      
      try {
        let fixedJson = jsonText.trim();
        const lastObj = fixedJson.lastIndexOf('}');
        if (lastObj > 0) {
          fixedJson = fixedJson.substring(0, lastObj + 1);
          if (!fixedJson.endsWith(']}')) fixedJson += ']}';
          const parsed = JSON.parse(fixedJson);
          albums = parsed.albums || (Array.isArray(parsed) ? parsed : []);
          console.log(`Recuperados ${albums.length} álbumes (truncado)`);
        }
      } catch {
        const albumRegex = /\{"position"\s*:\s*(\d+)\s*,\s*"artist"\s*:\s*"([^"]*)"\s*,\s*"title"\s*:\s*"([^"]*)"\s*(?:,\s*"year"\s*:\s*(\d+|null))?\s*(?:,\s*"confidence"\s*:\s*([\d.]+))?\s*(?:,\s*"spine_x_start"\s*:\s*([\d.]+))?\s*(?:,\s*"spine_x_end"\s*:\s*([\d.]+))?\s*\}/g;
        let match;
        while ((match = albumRegex.exec(jsonText)) !== null) {
          albums.push({
            position: parseInt(match[1]),
            artist: match[2],
            title: match[3],
            year: match[4] && match[4] !== 'null' ? parseInt(match[4]) : undefined,
            confidence: match[5] ? parseFloat(match[5]) : undefined,
            spine_x_start: match[6] ? parseFloat(match[6]) : undefined,
            spine_x_end: match[7] ? parseFloat(match[7]) : undefined,
          });
        }
        if (albums.length > 0) console.log(`Regex recuperó ${albums.length}`);
      }
    }
    
    console.log(`Resultado: ${albums.length} álbumes en ${processingTime}s`);

    const result: Record<string, unknown> = { albums, processingTime, model: usedModel, imageUrl };
    if (albums.length === 0) {
      result._debug = { finishReason, responsePreview: responseText.substring(0, 800), parseError };
    }

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });

  } catch (error) {
    console.error("Error:", error.message);
    return new Response(
      JSON.stringify({ error: error.message, albums: [] }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 200 }
    );
  }
});
