// Supabase Edge Function: smart-recommend
// Recibe una lista pre-filtrada de álbumes + la petición del usuario
// y usa Gemini para elegir los mejores con razonamiento personalizado.
//
// Flujo de 2 pasos:
//   1. analyze-music-intent (gemini-2.0-flash-lite) → extrae géneros baratos
//   2. smart-recommend (gemini-2.0-flash) → elige inteligentemente entre los filtrados
//
// Para desplegar:
//   supabase functions deploy smart-recommend --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
// Modelo estándar flash: buen razonamiento a bajo coste
const GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SYSTEM_PROMPT = `Eres un experto musicólogo, DJ y sommelier musical. 
El usuario te pide una recomendación y tienes acceso a su colección de vinilos (ya pre-filtrada por género).

Tu trabajo es elegir los 3-5 mejores álbumes de la lista para la ocasión que describe el usuario.

DEBES responder ÚNICAMENTE con un JSON válido con esta estructura exacta:
{
  "recommendations": [
    {
      "album_id": "string (el id del álbum)",
      "reason": "string (1-2 frases explicando por qué este disco encaja perfectamente)"
    }
  ],
  "mood_summary": "string (una frase corta y evocadora describiendo el mood, ej: 'Jazz suave para una velada íntima')"
}

Reglas:
- Elige entre 3 y 5 álbumes, ordenados del más recomendado al menos.
- Las razones deben ser personales, evocadoras y breves (no genéricas).
- Si ningún álbum encaja bien, devuelve los que más se acerquen con razón honesta.
- mood_summary debe ser una frase inspiradora de máximo 8 palabras.
- NO inventes álbumes. Solo usa los que están en la lista.`;

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

    const { query, albums } = await req.json();

    if (!query || !albums || !Array.isArray(albums) || albums.length === 0) {
      return new Response(
        JSON.stringify({ error: "Missing 'query' or 'albums' array" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Construir la lista de álbumes como texto compacto para el prompt
    const albumList = albums.map((a: any, i: number) => 
      `${i + 1}. [${a.id}] ${a.artist} — ${a.title}${a.year ? ` (${a.year})` : ''}${a.genres?.length ? ` | ${a.genres.join(', ')}` : ''}${a.styles?.length ? ` | ${a.styles.join(', ')}` : ''}`
    ).join('\n');

    console.log(`Smart recommend: "${query}" with ${albums.length} albums`);

    const userPrompt = `Petición del usuario: "${query}"

Álbumes disponibles en su colección (${albums.length} discos pre-filtrados):
${albumList}

Elige los mejores para esta ocasión.`;

    const geminiResponse = await fetch(`${GEMINI_API_URL}?key=${GEMINI_API_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        system_instruction: {
          parts: [{ text: SYSTEM_PROMPT }],
        },
        contents: [
          {
            parts: [{ text: userPrompt }],
          },
        ],
        generationConfig: {
          temperature: 0.7, // Un poco más creativo para recomendaciones
          maxOutputTokens: 600,
          responseMimeType: "application/json",
          responseSchema: {
            type: "OBJECT",
            properties: {
              recommendations: {
                type: "ARRAY",
                items: {
                  type: "OBJECT",
                  properties: {
                    album_id: { type: "STRING" },
                    reason: { type: "STRING" },
                  },
                  required: ["album_id", "reason"],
                },
              },
              mood_summary: { type: "STRING" },
            },
            required: ["recommendations", "mood_summary"],
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
    const responseText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!responseText) {
      console.error("No response text from Gemini:", JSON.stringify(geminiData));
      return new Response(
        JSON.stringify({ error: "Empty response from Gemini" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Parsear respuesta
    let parsedResult;
    try {
      if (typeof responseText === "object") {
        parsedResult = responseText;
      } else {
        const cleanText = responseText
          .replace(/```json\n?/g, "")
          .replace(/```\n?/g, "")
          .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, "")
          .trim();
        parsedResult = JSON.parse(cleanText);
      }
    } catch (parseError) {
      try {
        const jsonMatch = responseText.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          parsedResult = JSON.parse(jsonMatch[0]);
        } else {
          throw new Error("No JSON found");
        }
      } catch {
        console.error("Failed to parse:", responseText);
        return new Response(
          JSON.stringify({ error: "Failed to parse AI response" }),
          { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
    }

    console.log("Smart recommendation:", JSON.stringify(parsedResult));

    return new Response(
      JSON.stringify(parsedResult),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("smart-recommend error:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
