# DAL Plugin Checklist (Zoom/Teams)

Este checklist cubre el tramo final para instalar un plugin DAL real de camara virtual en macOS para apps como Zoom, Teams y navegadores.

## 1) Preparar target de plugin DAL real

- Crear un target `bundle`/`plugin` separado para CoreMediaIO (no solo scaffold).
- Implementar interfaces CMIO:
  - dispositivo virtual
  - stream provider
  - control de formatos/resoluciones/FPS
- Conectar pull de frames desde el app hacia el plugin (bridge compartido o IPC robusto).

## 2) IDs, signing y entitlements

- Definir `PRODUCT_BUNDLE_IDENTIFIER` unico del plugin.
- Configurar `DEVELOPMENT_TEAM` y firma valida en app + plugin.
- Revisar que el host tenga permisos de camara/microfono cuando aplique.
- Usar `hardened runtime` segun distribucion (dev vs release).

## 3) Empaquetado e instalacion del plugin

- El bundle DAL debe quedar en:
  - `/Library/CoreMediaIO/Plug-Ins/DAL/`
- Verificar estructura final del bundle e `Info.plist`.
- Reiniciar apps consumidoras (Zoom/Teams/Chrome) tras instalar.

## 4) Registro y validacion en sistema

- Confirmar que el dispositivo virtual aparece en:
  - Zoom (Video settings)
  - Teams (Device settings)
  - Google Meet (browser camera selector)
- Validar formatos soportados:
  - 1280x720 @ 30 FPS minimo
  - 1920x1080 @ 30 FPS opcional

## 5) Pruebas de estabilidad

- Correr sesiones largas (30-60 min) y medir:
  - FPS
  - latencia extremo a extremo
  - uso de memoria y picos
- Probar reconexion de camara fisica y sleep/wake del Mac.
- Verificar que no haya frame drops severos cuando CPU/GPU esten altas.

## 6) Calidad visual final

- Afinar mapeo de landmarks y region weights por avatar.
- Ajustar filtros temporales (alpha/Kalman) para eliminar jitter.
- Ajustar feather alpha en bordes para evitar recortes visibles.

## 7) Distribucion

- Para uso interno: script de instalacion con permisos admin.
- Para distribucion externa: notarizacion y pipeline de firma completo.
- Documentar rollback/uninstall del plugin DAL.
