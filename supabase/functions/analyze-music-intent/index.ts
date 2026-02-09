// Supabase Edge Function: analyze-music-intent
// Analiza la intención musical del usuario usando Gemini AI
//
// Para desplegar:
// 1. supabase secrets set GEMINI_API_KEY=tu_api_key
// 2. supabase functions deploy analyze-music-intent --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
// gemini-2.0-flash: buen equilibrio coste/calidad para entender matices musicales
const GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SYSTEM_PROMPT = `Eres un experto musicólogo y DJ con décadas de experiencia. Analizas la petición del usuario y determines los filtros musicales EXACTOS que encajan con su estado de ánimo.

IMPORTANTE: Cada petición es DIFERENTE. NO uses géneros genéricos por defecto. Lee la petición con atención y elige SOLO los géneros/estilos que realmente encajan.

Responde ÚNICAMENTE con JSON válido con esta estructura:
{
  "genres": ["string"],
  "styles": ["string"],
  "year_start": number or null,
  "year_end": number or null,
  "mood_description": "string (frase evocadora de máx 8 palabras)",
  "energy": "low" | "medium" | "high",
  "keywords": ["string"]
}

EJEMPLOS de cómo mapear peticiones a géneros:

"cena romántica con mi pareja" → genres: ["Jazz", "Folk, World, & Country"], styles: ["Bossa Nova", "Soul", "Ballad", "Easy Listening"], energy: "low"

"quiero algo para hacer deporte, energía alta" → genres: ["Electronic", "Hip Hop"], styles: ["Techno", "Drum n Bass", "Electro", "Hardcore"], energy: "high"

"algo melancólico, estoy triste" → genres: ["Rock"], styles: ["Shoegaze", "Sadcore", "Slowcore", "Post-Rock", "Dream Pop", "Ambient"], energy: "low"

"música para conducir por carretera" → genres: ["Rock"], styles: ["Classic Rock", "Indie Rock", "Stoner Rock", "Psychedelic Rock"], energy: "medium"

"fiesta con amigos, bailable" → genres: ["Electronic", "Funk / Soul"], styles: ["House", "Disco", "Nu-Disco", "Synth-pop", "Dance-pop"], energy: "high"

"grita con el alma, desahógate" → genres: ["Rock"], styles: ["Punk", "Post-Punk", "Hardcore", "Noise", "Garage Rock", "Grunge"], energy: "high"

"relajarme antes de dormir" → genres: ["Electronic"], styles: ["Ambient", "Downtempo", "Minimal", "New Age"], energy: "low"

Reglas:
- "genres" usa nombres estándar de Discogs: "Rock", "Electronic", "Jazz", "Funk / Soul", "Pop", "Hip Hop", "Classical", "Latin", "Reggae", "Blues", "Folk, World, & Country", "Stage & Screen".
- "styles" son MÁS ESPECÍFICOS y son los que realmente diferencian. Incluye 4-8 estilos relevantes.
- NO incluyas géneros que no encajen con la petición. "Dance" y "Disco" NO encajan con "algo triste".
- "keywords" pueden ser nombres de artistas o palabras que sugiera la petición.
- Si no se menciona un rango de años, pon null.`;

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (!GEMINI_API_KEY) {
      return new Response(
        JSON.stringify({ error: "GEMINI_API_KEY not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { query } = await req.json();

    if (!query || typeof query !== "string" || query.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: "Missing or empty 'query' parameter" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    console.log(`Analyzing music intent: "${query}"`);

    const geminiResponse = await fetch(`${GEMINI_API_URL}?key=${GEMINI_API_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        system_instruction: {
          parts: [{ text: SYSTEM_PROMPT }],
        },
        contents: [
          {
            parts: [{ text: `Petición del usuario: "${query}"` }],
          },
        ],
        generationConfig: {
          temperature: 0.3,
          maxOutputTokens: 500,
          responseMimeType: "application/json",
          responseSchema: {
            type: "OBJECT",
            properties: {
              genres: { type: "ARRAY", items: { type: "STRING" } },
              styles: { type: "ARRAY", items: { type: "STRING" } },
              year_start: { type: "INTEGER", nullable: true },
              year_end: { type: "INTEGER", nullable: true },
              mood_description: { type: "STRING" },
              energy: { type: "STRING", enum: ["low", "medium", "high"] },
              keywords: { type: "ARRAY", items: { type: "STRING" } },
            },
            required: ["genres", "styles", "mood_description", "energy", "keywords"],
          },
        },
      }),
    });

    if (!geminiResponse.ok) {
      const errorText = await geminiResponse.text();
      console.error("Gemini API error:", errorText);
      return new Response(
        JSON.stringify({ error: "Gemini API error", details: errorText }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const geminiData = await geminiResponse.json();
    
    // Extraer el texto de la respuesta
    const responseText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;
    
    if (!responseText) {
      console.error("No response text from Gemini:", JSON.stringify(geminiData));
      return new Response(
        JSON.stringify({ error: "Empty response from Gemini" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parsear el JSON de la respuesta
    let parsedResult;
    try {
      // Si Gemini ya devolvió un objeto (con responseMimeType: "application/json")
      if (typeof responseText === "object") {
        parsedResult = responseText;
      } else {
        // Limpiar posibles backticks de markdown y caracteres de control
        let cleanText = responseText
          .replace(/```json\n?/g, "")
          .replace(/```\n?/g, "")
          // Eliminar caracteres de control invisibles (excepto \n, \r, \t)
          .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, "")
          .trim();
        parsedResult = JSON.parse(cleanText);
      }
    } catch (parseError) {
      // Segundo intento: extraer el primer objeto JSON con regex
      try {
        const jsonMatch = responseText.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          parsedResult = JSON.parse(jsonMatch[0]);
        } else {
          throw new Error("No JSON object found in response");
        }
      } catch (secondError) {
        console.error("Failed to parse Gemini response (both attempts):", responseText);
        return new Response(
          JSON.stringify({ 
            error: "Failed to parse AI response", 
            raw_response: typeof responseText === "string" ? responseText.substring(0, 500) : JSON.stringify(responseText)
          }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    console.log("Music intent result:", JSON.stringify(parsedResult));

    return new Response(
      JSON.stringify(parsedResult),
      { 
        status: 200, 
        headers: { ...corsHeaders, "Content-Type": "application/json" } 
      }
    );
  } catch (error) {
    console.error("analyze-music-intent error:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
