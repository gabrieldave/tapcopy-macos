# TapCopy — Píldora Camaleón (v1.0.2)

Utilidad nativa de **BLACK EYE** para macOS: selecciona texto en cualquier app
(Chrome, Brave, Arc, Safari, Cursor, VS Code, PDFs y apps nativas) y aparece una
píldora inteligente flotante sin robar el foco.

- **Swift 5.10 + AppKit puro** (`0.0%` CPU en reposo, cero dependencias externas).
- **4 funciones de Píldora Camaleón integradas** (conmutables desde la barra de menús):
  1. **Detección contextual de entidades**: abre URLs/dominios, revela rutas existentes en Finder, muestra swatch real `#HEX ↔ RGB` y resuelve operaciones matemáticas al vuelo (`= resultado`).
  2. **Limpieza y transformación rápida**: botón `Plano` (sin estilos ni saltos rotos) y menú `Aa` (`MAYÚSCULAS`, `minúsculas`, `Tipo Título`, `snake_case`, `camelCase`, bloque Markdown y conteo de palabras/caracteres).
  3. **Búsqueda web sin foco**: lupa directa en Google (y búsqueda de código en GitHub / StackOverflow dentro de `Aa`).
  4. **Estante flotante (`Pin`)**: fija hasta 4 fragmentos arrastrables en pantalla sin sobrescribir tu portapapeles principal.
- **Motor Anti-Traslape (`WindowCollisionAvoidance`)**: posicionamiento inferior inteligente que deja libre la franja superior de Notion/ChatGPT/Medium y detecta vía `CGWindowList` menús flotantes de terceros (PopClip, Raycast, DeepL, Grammarly) reacomodándose sin chocar.
- Firma Developer ID `YH6W55MP95`, Hardened Runtime, notarización `ordena-notary` y *stapling* doble.

## Compilar e instalar

Instalación rápida local firmada con Developer ID:

```bash
./scripts/build_and_notarize.sh --dev
```

Si macOS dejó desincronizado el permiso de Accesibilidad tras compilaciones previas:

```bash
./scripts/build_and_notarize.sh --dev --reset-tcc
```

Pipeline completo de release (DMG + notarización + stapling):

```bash
./scripts/build_and_notarize.sh
```
