# TapCopy · Sitio comercial (WEB_FACTORY · Arquetipo 04 Kinetic SaaS Command)

Sitio bilingüe EN | ES de **tapcopy.iareal.net**, listo para Cloudflare Pages.

```bash
cd web
node build.mjs   # genera public/ desde src/i18n/*.json + src/templates/*.html
npm test         # pruebas del enrutado por idioma
python3 -m http.server -d public 8080   # vista previa local (sin geolocalización)
```

| Ruta | Qué es |
|---|---|
| `src/i18n/en.json`, `src/i18n/es.json` | Todo el copy. Editar aquí, nunca en `public/`. |
| `src/templates/` | Plantillas de landing y páginas legales. |
| `site.config.json` | Dominio, precios bloqueados, endpoints, ID de YouTube, WhatsApp. |
| `functions/_middleware.js` | Idioma por cookie → país → Accept-Language, `Vary`, sin redirigir bots. |
| `public/assets/site.js` | Hero vivo, analizador Camaleón, Estante Pin, Lite-YouTube, formulario de prueba. |
| `HANDOFF_OPENCODE.json` | Transferencia para integración backend. |

Despliegue en Cloudflare Pages: *Build command* `node build.mjs`, *Build output* `public`, *Root directory* `web`.

La especificación de la ventana de licencia de macOS está en `../docs/licensing/`.
