// Supabase Edge Function: discogs-proxy
// Proxy para la API de Discogs (evita CORS en web)
//
// Para desplegar:
// 1. supabase secrets set DISCOGS_TOKEN=your_token_here
// 2. supabase functions deploy discogs-proxy

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const DISCOGS_TOKEN = Deno.env.get("DISCOGS_TOKEN");
const DISCOGS_BASE_URL = "https://api.discogs.com";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

serve(async (req: Request) => {
  // Preflight CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);

    // === Modo Image Proxy ===
    // Si recibe ?image_url=..., descarga la imagen y la devuelve con CORS headers.
    // Útil para mostrar carátulas de Discogs en Flutter web (que no tiene CORS).
    const imageUrl = url.searchParams.get("image_url");
    if (imageUrl) {
      const imgResponse = await fetch(imageUrl, {
        headers: {
          "User-Agent": "VinylScout/1.0",
          ...(DISCOGS_TOKEN ? { "Authorization": `Discogs token=${DISCOGS_TOKEN}` } : {}),
        },
      });

      if (!imgResponse.ok) {
        return new Response(`Image fetch failed: ${imgResponse.status}`, {
          status: imgResponse.status,
          headers: corsHeaders,
        });
      }

      const contentType = imgResponse.headers.get("content-type") || "image/jpeg";
      const imageData = await imgResponse.arrayBuffer();

      return new Response(imageData, {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": contentType,
          "Cache-Control": "public, max-age=86400", // Cache 24h
        },
      });
    }

    // === Modo API Search ===
    const query = url.searchParams.get("q") || "";
    const type = url.searchParams.get("type") || "release";
    const perPage = url.searchParams.get("per_page") || "8";

    // Parámetros adicionales opcionales (para búsqueda de novedades)
    const format = url.searchParams.get("format");     // e.g. "Vinyl"
    const year = url.searchParams.get("year");           // e.g. "2026"
    const genre = url.searchParams.get("genre");         // e.g. "Rock"
    const style = url.searchParams.get("style");         // e.g. "Post-Punk"
    const sort = url.searchParams.get("sort");           // e.g. "year"
    const sortOrder = url.searchParams.get("sort_order"); // e.g. "desc"

    // Necesitamos al menos q o genre para hacer una búsqueda válida
    if (!query && !genre && !style && !format) {
      return new Response(
        JSON.stringify({ error: "Missing search parameters (q, genre, style, or format)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!DISCOGS_TOKEN) {
      return new Response(
        JSON.stringify({ error: "DISCOGS_TOKEN not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Construir URL con todos los parámetros
    const params = new URLSearchParams();
    if (query) params.set("q", query);
    params.set("type", type);
    params.set("per_page", perPage);
    if (format) params.set("format", format);
    if (year) params.set("year", year);
    if (genre) params.set("genre", genre);
    if (style) params.set("style", style);
    if (sort) params.set("sort", sort);
    if (sortOrder) params.set("sort_order", sortOrder);

    const discogsUrl = `${DISCOGS_BASE_URL}/database/search?${params.toString()}`;
    
    console.log(`Discogs proxy: searching "${query}" genre=${genre} year=${year} format=${format}`);

    const response = await fetch(discogsUrl, {
      headers: {
        "User-Agent": "VinylScout/1.0",
        "Authorization": `Discogs token=${DISCOGS_TOKEN}`,
      },
    });

    console.log(`Discogs response: ${response.status} ${response.statusText}`);

    // Si Discogs devuelve error, devolver el texto tal cual
    if (!response.ok) {
      const errorText = await response.text();
      console.error(`Discogs error (${response.status}): ${errorText.substring(0, 300)}`);
      return new Response(
        JSON.stringify({ error: `Discogs ${response.status}: ${response.statusText}`, results: [] }),
        {
          status: 200, // Devolver 200 para que el cliente no crashee
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const data = await response.json();

    return new Response(
      JSON.stringify(data),
      {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      }
    );
  } catch (error) {
    console.error("Discogs proxy error:", error);
    return new Response(
      JSON.stringify({ error: error.message, results: [] }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
