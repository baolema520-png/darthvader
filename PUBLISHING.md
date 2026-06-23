# Publicacion VirtualFaceCam (macOS)

Este flujo asume que ya validaste funcionalmente la app con `VirtualFaceCam` en Zoom/Meet/Teams.

## 1) Build release

```bash
./Scripts/build_release_app.sh
```

Genera:

- `build-artifacts/VirtualFaceCamApp.app`
- `build-artifacts/VirtualFaceCamApp.zip`

## 2) Prepublish checks

```bash
./Scripts/prepublish_check.sh
```

Verifica firma, `spctl`, estado de extension CMIO y enumeracion de camaras.

## 3) Notarizacion + staple

Define credenciales:

```bash
export APPLE_ID="tu-apple-id@icloud.com"
export TEAM_ID="TU_TEAM_ID"
export APP_PASSWORD="app-specific-password"
```

Ejecuta:

```bash
./Scripts/notarize_and_staple.sh
```

## 4) Crear DMG final

```bash
./Scripts/package_dmg.sh
```

Resultado:

- `build-artifacts/VirtualFaceCamApp.dmg`

## 5) Smoke test final antes de distribuir

1. Instalar desde DMG en `/Applications`.
2. Abrir app, activar extension y pulsar `Start`.
3. En Zoom/Meet/Teams seleccionar `VirtualFaceCam`.
4. Verificar modo `Avatar` con foto cargada y ajuste de sliders.
