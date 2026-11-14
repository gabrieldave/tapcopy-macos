# TapCopy v1.1.0 · Ventana de Prueba / Activación de Licencia

**Destino:** `Sources/TapCopy/LicenseWindowController.swift` (AppKit puro, sin SwiftUI)
**Estilo:** Cupertino oscuro, coherente con `AboutWindowController` y `PillPalette`
**Estado:** Especificación de diseño lista para integrar. Los puntos marcados **[APROBACIÓN DG]** requieren visto bueno del Director General antes de implementarse.
**Referencias:** `license-window-wireframe.html` (maqueta 1:1 de los 5 estados) y `LicenseWindowController.swift` (esqueleto de referencia, sin compilar en CI).

---

## 1. Ventana

| Propiedad | Valor |
|---|---|
| Clase | `NSWindow` (no `NSPanel`: debe poder recibir foco de teclado para escribir la clave) |
| `contentRect` | **480 × 440 pt** (fijo, no redimensionable) |
| `styleMask` | `[.titled, .closable, .fullSizeContentView]` |
| `titlebarAppearsTransparent` | `true` · `titleVisibility = .hidden` · `isMovableByWindowBackground = true` |
| `appearance` | `NSAppearance(named: .darkAqua)` (siempre oscura, igual que Acerca de) |
| Fondo | `NSVisualEffectView` · `material = .underWindowBackground` · `blendingMode = .behindWindow` · `state = .active` |
| Nivel | `.normal`; al abrirse: `NSApp.activate(ignoringOtherApps: true)` + `makeKeyAndOrderFront` + `center()` |
| Cierre | Botón rojo y `Esc` = “Seguir probando” (en estado vencido, `Esc` solo cierra; no desbloquea) |
| `isReleasedWhenClosed` | `false` (singleton `LicenseWindowController.shared`, igual que `AboutWindowController`) |

## 2. Rejilla y medidas (pt)

Margen lateral **28**. Ancho útil **424**. Origen superior (debajo de la barra de título transparente de 28 pt).

```
 y=0    ┌──────────────────────────────────────────────── 480 ─┐
        │ ● ● ●                                  (titlebar 28)  │
 y=40   │                    [ icono 64×64 ]                    │
 y=112  │                 TapCopy                 20 semibold   │
 y=138  │        Prueba gratis · quedan 9 días     12 regular   │
 y=168  │ ┌─ Tarjeta de prueba 424×68 · r12 ─────────────────┐  │
        │ │ PRUEBA GRATIS                    Día 5 de 14     │  │
        │ │ ███████████████░░░░░░░░░░░░░░░░  barra 6 pt r3   │  │
        │ └──────────────────────────────────────────────────┘  │
 y=258  │ Activar licencia                         13 semibold  │
 y=282  │ ┌─ Campo clave 424×38 · r8 ─────────────────────────┐ │
        │ │ TCOPY-XXXX                     SF Mono 15 medium  │ │
        │ └───────────────────────────────────────────────────┘ │
 y=326  │ ⓘ Línea de estado (12 regular, 2 líneas máx.)         │
 y=388  │ Comprar licencia ↗            [Seguir probando] [Activar] │
        └───────────────────────────────────────────────────────┘
 y=440
```

Espaciados verticales: icono→título 8 · título→subtítulo 2 · subtítulo→tarjeta 22 · tarjeta→sección 22 · sección→campo 8 · campo→estado 8 · fila de botones anclada a 24 pt del borde inferior.

## 3. Tokens visuales

| Token | Valor | Uso |
|---|---|---|
| `accent` | `#38BDF8` (`PillPalette.accent`) | Barra de prueba activa, foco del campo, enlace “Comprar licencia” |
| `success` | `#10B981` (`PillPalette.success`) | Estado con licencia, check ✓ |
| `warning` | `NSColor.systemOrange` | Barra y subtítulo cuando quedan ≤ 3 días |
| `danger` | `NSColor.systemRed` | Prueba vencida, errores de activación |
| Tarjeta | fondo `white @ 0.06`, borde `white @ 0.10` 1 pt, radio 12 | Tarjeta de prueba |
| Campo | fondo `black @ 0.25`, borde `white @ 0.15` 1 pt, radio 8; foco: borde `accent` + anillo `accent @ 0.25` 3 pt | Clave |
| Texto principal | `.labelColor` | Título, valores |
| Texto secundario | `.secondaryLabelColor` | Subtítulo, etiquetas |
| Tipografía | `NSFont.systemFont` (SF Pro). Números: `.monospacedDigitSystemFont`. Clave: `.monospacedSystemFont(ofSize: 15, weight: .medium)` | Cero fuentes externas |

Botones: `Activar` = `bezelStyle .rounded`, `keyEquivalent = "\r"`, `bezelColor = accent` (botón por defecto). `Seguir probando` = `.rounded` estándar. `Comprar licencia ↗` = `NSButton` con `isBordered = false`, `contentTintColor = accent`, 13 pt medium.

## 4. Estados

| # | Estado | Subtítulo | Tarjeta | Botones | Notas |
|---|---|---|---|---|---|
| A | `trialActive(daysLeft 4…14)` | “Prueba gratis · quedan N días” | Barra `accent`, “Día X de 14” | Comprar ↗ · Seguir probando · **Activar** | Activar deshabilitado hasta que la clave tenga formato válido |
| B | `trialEndingSoon(daysLeft 1…3)` | En `warning` | Barra `warning` | Igual que A | Se muestra sola 1 vez al día (día 11–14) |
| C | `trialExpired` | “Tu prueba de 14 días terminó” en `danger` | Barra llena `danger`, “14 de 14” | Comprar ↗ · Salir de TapCopy · **Activar** | La píldora deja de aparecer; menú de barra muestra “Activar licencia…” |
| D | `activating` | sin cambio | sin cambio | Todo deshabilitado; `NSProgressIndicator` `.spinning` 16 pt a la izquierda de Activar | Timeout de red 15 s |
| E | `licensed(plan)` | “Licencia Personal · 1 Mac” / “Licencia Pro · hasta 3 Macs” en `success` | Tarjeta muestra clave enmascarada `TCOPY-••••-••••-7F3A` + ✓ | Desactivar esta Mac · **Listo** | Campo de clave oculto |

**Errores (estado A/B/C + línea de estado en `danger`, el campo hace shake horizontal 3× 6 pt, 0.3 s):**

| Código | EN | ES |
|---|---|---|
| `format` | Keys look like TCOPY-XXXX. Check for typos. | Las claves tienen la forma TCOPY-XXXX. Revisa que esté bien escrita. |
| `invalid_key` | That key isn't valid. Check it and try again. | Esa clave no es válida. Revísala e inténtalo de nuevo. |
| `seat_limit` | This key is already active on its maximum number of Macs. | Esta clave ya está activa en el máximo de Macs de su plan. |
| `refunded` | This license was refunded and is no longer active. | Esta licencia fue reembolsada y ya no está activa. |
| `network` | Couldn't reach the activation server. Check your connection. | No pudimos conectar con el servidor de activación. Revisa tu conexión. |

## 5. Campo de clave

- Placeholder: `TCOPY-XXXX`.
- Al escribir/pegar: `uppercased()`, se eliminan espacios y saltos de línea, solo `[A-Z0-9-]`.
- Validación local de formato: `^TCOPY-[A-Z0-9]{4}(-[A-Z0-9]{4}){0,3}$`. **[APROBACIÓN DG]** La longitud final de la clave la define backend; el regex admite de 1 a 4 grupos.
- `Activar` se habilita solo con formato válido. `Return` activa.
- VoiceOver: `setAccessibilityLabel("License key")` / `"Clave de licencia"`.

## 6. Copy bilingüe (EN | ES)

| Clave | EN | ES |
|---|---|---|
| windowTitle | TapCopy License | Licencia de TapCopy |
| trialLabel | FREE TRIAL | PRUEBA GRATIS |
| daysLeft | Free trial · %d days left | Prueba gratis · quedan %d días |
| dayOne | Free trial · last day | Prueba gratis · último día |
| dayOf | Day %d of 14 | Día %d de 14 |
| expired | Your 14-day trial has ended | Tu prueba de 14 días terminó |
| activateSection | Activate license | Activar licencia |
| keyPlaceholder | TCOPY-XXXX | TCOPY-XXXX |
| activate | Activate | Activar |
| continueTrial | Continue Trial | Seguir probando |
| buy | Buy License ↗ | Comprar licencia ↗ |
| quit | Quit TapCopy | Salir de TapCopy |
| licensedPersonal | Personal License · 1 Mac | Licencia Personal · 1 Mac |
| licensedPro | Pro License · up to 3 Macs | Licencia Pro · hasta 3 Macs |
| updates | v1.x updates included | Actualizaciones v1.x incluidas |
| deactivate | Deactivate This Mac | Desactivar esta Mac |
| done | Done | Listo |
| activated | ✓ License activated. Thank you! | ✓ Licencia activada. ¡Gracias! |
| menuItem | License… | Licencia… |

“Comprar licencia ↗” abre `https://tapcopy.iareal.net/#pricing` (EN) o `https://tapcopy.iareal.net/es/#pricing` (ES) según el idioma activo en Acerca de.

## 7. Cuándo se abre

1. Menú de barra → nuevo ítem **“Licencia…”** debajo de “Acerca de TapCopy…”.
2. Automáticamente una vez al día en los días 11–14 (estado B), nunca mientras el usuario está seleccionando (esperar a que `SelectionMonitor` esté en reposo ≥ 2 s).
3. Al vencer: la próxima selección no muestra la píldora; abre el estado C una vez por sesión.
4. Acerca de: la línea de estado añade “Prueba: quedan N días” o “Licencia Pro”.

## 8. Propuesta técnica para backend **[APROBACIÓN DG]**

Hoy la app no hace ninguna petición de red (README). La activación introduciría la primera; el sitio y el README deben decirlo (“solo la activación de licencia contacta nuestro servidor; tu texto nunca sale de tu Mac”).

- **Reloj de prueba:** fecha del primer arranque en Llavero (`kSecClassGenericPassword`, servicio `net.iareal.tapcopy.trial`) para que no se reinicie al borrar `UserDefaults`.
- **Activar:** `POST https://tapcopy.iareal.net/api/license/activate`
  `{ "key": "TCOPY-…", "deviceId": "<SHA-256 de IOPlatformUUID + sal>", "appVersion": "1.1.0", "lang": "es" }`
  → `200 { "status": "active", "plan": "personal|pro", "seats": 1|3, "seatsUsed": n, "token": "<firma Ed25519>" }`
  → `4xx { "error": "invalid_key|seat_limit|refunded" }`
- **Verificación offline:** el token firmado se guarda en Llavero y se valida localmente con la clave pública embebida; sin llamadas periódicas.
- **Desactivar:** `POST /api/license/deactivate { key, deviceId }` libera el asiento.
