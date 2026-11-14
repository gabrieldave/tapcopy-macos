# TapCopy

Utilidad interna de **BLACK EYE** para macOS: selecciona texto en cualquier app
(Chrome, Brave, Arc, Safari, apps nativas) y aparece una píldora **Copiar**
junto al cursor. Un clic copia la selección.

- Swift puro + AppKit. Sin Electron, sin dependencias externas.
- Sin copiado automático y sin tocar el portapapeles al leer la selección.
- Píldora flotante que nunca roba el foco (`NSPanel` no activante).
- Icono de barra de menús, arranque al inicio y About bilingüe EN | ES.
- Firma Developer ID `YH6W55MP95`, Hardened Runtime, notarización y *stapling*
  doble (app + DMG).

## Requisitos

- macOS 14 o superior (Apple Silicon).
- Xcode 15+ / Swift 5.10+.
- Perfil de notarización de `notarytool` llamado `ordena-notary`.

## Compilar e instalar

```bash
./scripts/build_and_notarize.sh
```

El script genera el icono, compila en release, firma, empaqueta el DMG,
notariza, engrapa app y DMG, y instala en `/Applications/TapCopy.app`.

Para subir la versión patch antes de compilar:

```bash
./scripts/build_and_notarize.sh --bump
```

La versión vive en `version.txt` (primera línea: versión, segunda: build).

## Uso

1. Primer arranque: acepta el permiso de **Accesibilidad** (el icono del Dock
   permanece visible hasta que lo ocultes desde el menú).
2. Selecciona texto con el ratón o doble clic.
3. Pulsa **Copiar** en la píldora. Si la app no responde a Cmd+C, TapCopy
   escribe el texto leído vía Accessibility directamente en el portapapeles.

Clic derecho en el icono de la barra de menús: encender/apagar al instante.

## Estructura

```
Sources/TapCopy/
  main.swift                    Arranque NSApplication
  AppDelegate.swift             Ciclo de vida, menú principal, política de Dock
  SignatureVerifier.swift       Team ID + chip real vía sysctl
  PermissionManager.swift       TCC de Accesibilidad sin polling residual
  SelectionMonitor.swift        Gestos de ratón + extracción AX
  TapCopyPanelController.swift  Píldora flotante y copiado
  StatusBarController.swift     Icono de barra de menús y ajustes
  AboutWindowController.swift   Ventana Acerca de bilingüe
scripts/
  GenerateIcon.swift            Icono con CoreGraphics + iconutil
  build_and_notarize.sh         Pipeline de release
```
