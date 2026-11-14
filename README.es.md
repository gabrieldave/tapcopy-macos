<div align="center">

# 📋 TapCopy

**Selecciona. Clic. Copiado.**

Utilidad nativa de macOS de **BLACK EYE** que convierte cualquier selección de texto en una acción de un solo clic: sin atajos, sin robar el foco.

[**English**](README.md) · [**Español**](README.es.md)

</div>

&nbsp;

TapCopy observa tus gestos de selección, lee el texto con la API de Accesibilidad y muestra una pequeña *Píldora Camaleón* junto al cursor. Un clic copia. La misma píldora abre enlaces, revela archivos, convierte colores, resuelve operaciones, transforma texto, busca en la web o fija fragmentos en pantalla.

## ✨ ¿Por qué TapCopy?

Copiar un texto que ya seleccionaste no debería exigir el teclado. Hoy implica buscar ⌘C, perder el hilo o instalar una extensión que solo funciona dentro de un navegador.

TapCopy funciona en cualquier app donde macOS exponga una selección — Chrome, Brave, Arc, Safari, Cursor, VS Code, PDFs y apps nativas — manteniendo viva tu selección azul. Nunca toca el portapapeles al leer, nunca abre una petición de red y nunca pide Grabación de Pantalla. Todo se calcula localmente en Swift y AppKit.

## 📲 Descarga

TapCopy se distribuye como **DMG firmado y notarizado**, pero todavía no hay binarios publicados en GitHub. El repositorio incluye todo lo necesario para producir esa misma compilación en local.

**Requisitos**

- macOS 14 Sonoma o superior (Apple Silicon).
- Xcode 15+ / Swift 5.10+.
- Permiso de Accesibilidad (se solicita al primer arranque).
- Para firmar y notarizar: certificado `Developer ID Application` del equipo `YH6W55MP95` y un perfil de llavero de `notarytool` llamado `ordena-notary`.

**Compilar e instalar**

```bash
git clone https://github.com/gabrieldave/tapcopy-macos.git
cd tapcopy-macos

# Firmado, instalado en /Applications, sin DMG:
./scripts/build_and_notarize.sh --dev

# Release completo: DMG + notarización + doble stapling (app y DMG):
./scripts/build_and_notarize.sh
```

El pipeline escribe `VERSION`, `BUILD`, `SHA256` y la ruta del DMG en `dist/release-info.txt`.

## 🚀 Cómo funciona

1. **Instala y abre** TapCopy. La app vive en la barra de menús; si falta el permiso de Accesibilidad aparece el aviso inicial.
2. **Concede Accesibilidad** en Ajustes del Sistema → Privacidad y Seguridad → Accesibilidad. El icono pasa de triángulo de aviso a la silueta del portapapeles.
3. **Selecciona texto en cualquier app** — arrastra sobre una palabra o párrafo, doble clic en una palabra, o mayúsculas + clic para extender. TapCopy ignora clics sueltos y arrastres menores a 3,5 pt.
4. **Haz clic en un segmento** de la píldora que aparece junto al cursor:
   - **Copiar** copia la selección (⌘C a la app de origen, con el texto capturado como respaldo).
   - Los segmentos contextuales solo aparecen cuando aplican: **Abrir**, **Mostrar**, swatch de color o `= resultado`.
   - **Plano**, **Aa**, la lupa y el **pin** están disponibles con el Modo Camaleón encendido.
5. **Sigue trabajando.** La píldora se oculta a los 5 segundos, o al instante con `Esc`, clic derecho o scroll. La insignia ✓ confirma la acción.

Todo es local: sin cuenta, sin telemetría, sin subidas.

## 📖 Guías

Todavía no existe un sitio de documentación externo. Estos son los procedimientos verificados de la app y de su pipeline.

### Lista de primer arranque

- Confirma que la barra de menús muestre `TapCopy activo · Píldora Camaleón`.
- Pulsa **Probar píldora ahora** en el menú para ver la píldora sin seleccionar nada.
- Abre **Acerca de TapCopy…** para revisar versión, chip, estado de firma y Accesibilidad, y usa **Copiar diagnóstico** al reportar un problema.

### Referencia de la barra de menús

- **Clic izquierdo** — abre el menú completo.
- **Clic derecho** — enciende o apaga TapCopy al instante.
- **Modo Camaleón (4 funciones)** — activa o desactiva los cuatro segmentos inteligentes.
- **Pausar en *App*** — omite TapCopy en la app frontal; la elección se conserva.
- **Permiso de Accesibilidad** — abre el panel exacto de Ajustes del Sistema.
- **Ocultar icono del Dock** — alterna entre Dock y solo barra de menús.
- **Iniciar al encender mi Mac** — registra el inicio automático vía `SMAppService`.

### Solución de problemas

Si la píldora no aparece después de recompilar, macOS puede conservar una entrada de Accesibilidad obsoleta del binario anterior:

```bash
./scripts/build_and_notarize.sh --dev --reset-tcc
```

Después vuelve a activar TapCopy en Ajustes del Sistema. Los eventos de ejecución se escriben en `~/Library/Logs/TapCopy.log`: cada lectura de selección, la distancia de arrastre detectada, apps excluidas, cambios de TCC y reposicionamientos anti-traslape.

## 🔧 Funciones

### Píldora Camaleón

- Una sola cápsula compacta que crece únicamente con los segmentos que tienen sentido para la selección actual
- Nunca se vuelve ventana key ni main: la app de origen conserva el foco y tu selección sigue resaltada
- Detección de clics sobre la propia píldora para no disparar lecturas nuevas de selección

### Acciones contextuales

- **Abrir enlaces** — URLs completas y dominios sueltos como `findaro.iareal.net`, en tu navegador predeterminado
- **Revelar archivos** — rutas absolutas y con `~/` que existan en disco se abren en Finder con el elemento seleccionado
- **Conversión de color** — `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb()` y `rgba()` generan un swatch en vivo y copian la notación opuesta
- **Matemática en línea** — `145 * 1.16`, `×`, `÷`, `%`, paréntesis, `$` y separadores de miles, con un analizador propio que descarta fechas y teléfonos

### Herramientas de texto

- **Plano** — elimina estilos, espacios duros, caracteres de ancho cero, guiones suaves, espacios finales y saltos de línea repetidos
- **Aa** — `MAYÚSCULAS`, `minúsculas`, `Tipo Título`, `snake_case`, `camelCase` y bloque de código Markdown
- Conteo de palabras y caracteres en vivo dentro del menú `Aa`

### Búsqueda sin perder el foco

- El segmento de lupa abre una búsqueda en Google con la selección
- Si la selección parece código, también ofrece **Buscar código en GitHub** y **Buscar en StackOverflow**

### Estante de pines

- Fija hasta cuatro fragmentos como tarjetas flotantes que sobreviven al cambio de Space
- Las tarjetas se arrastran, muestran vista previa y copian a demanda: tu portapapeles principal no se toca hasta que lo pides
- La tarjeta más antigua se retira automáticamente al fijar la quinta

### Motor anti-traslape

- Seis posiciones candidatas alrededor del cursor, ajustadas al área visible de la pantalla
- Detecta barras flotantes de terceros (PopClip, Raycast, DeepL, Grammarly, LookUp) y barras dentro de la web vía `CGWindowList`, sin permiso de Grabación de Pantalla
- Prioriza la zona inferior del cursor, deja libre la franja superior para popovers web y revisa colisiones 160 ms después de aparecer
- Lee barras a nivel DOM (Gemini, Notion, ChatGPT, Claude, Medium, Google Docs) a través del árbol de Accesibilidad, así también esquiva popovers dentro de la página

### Integración con el sistema

- Barra de menús primero, icono de Dock opcional, inicio al encender el Mac
- Lista de apps pausadas guardada en `UserDefaults`
- Icono adaptativo: triángulo de aviso sin Accesibilidad, silueta hueca apagado, silueta rellena activo
- Ventana Acerca de bilingüe (ES / EN) con versión, chip, verificación de firma y exportación de diagnóstico
- Verificación de firma en ejecución contra el equipo `YH6W55MP95` y detección de hardware vía `sysctl`
- Firma Developer ID, Hardened Runtime, notarización y doble stapling (app + DMG)

## ❓ ¿Nuevo en GitHub?

No necesitas cuenta de GitHub para leer ni compilar este proyecto.

1. Abre el [repositorio](https://github.com/gabrieldave/tapcopy-macos).
2. Usa el botón verde **Code** → **Download ZIP** y descomprime, o clona con el comando de arriba.
3. Abre Terminal en la carpeta descomprimida y ejecuta `./scripts/build_and_notarize.sh --dev`.
4. Arrastra `TapCopy.app` desde `/Applications` a **Ajustes del Sistema → Privacidad y Seguridad → Accesibilidad** y actívalo.

Actualmente no hay archivos en **Releases**, porque el DMG notarizado se compila y verifica en local para cada versión.

## 📙 Contribuir

TapCopy es una herramienta interna de BLACK EYE publicada como repositorio público. Por ahora no se aceptan pull requests ni issues externos. Si trabajas dentro de BLACK EYE, mantén los cambios acotados, respeta los archivos protegidos (`main.swift`, `SignatureVerifier.swift`, `TapLog.swift`, `scripts/GenerateIcon.swift`) y sube `version.txt` en cada release.

## ❗ Acerca de

TapCopy está diseñado y desarrollado por **David DEL RIO COLIN** para BLACK EYE, en Swift puro con AppKit y sin dependencias de terceros. El icono se genera por código con `scripts/GenerateIcon.swift`; la píldora, el estante y el motor de colisiones son vistas AppKit propias, sin framework de UI externo.

La identidad interna, el logo y el icono son propiedad de BLACK EYE. No reutilices el nombre, el icono ni la identidad visual en compilaciones derivadas.

## 📜 Licencia

No hay archivo de licencia. TapCopy es software interno propietario: el código es público como referencia, pero todos los derechos están reservados y la redistribución, modificación o uso comercial requiere permiso escrito de BLACK EYE.

© 2026 BLACK EYE — David DEL RIO COLIN.
