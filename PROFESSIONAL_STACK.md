# Stack profesional integrado

## Objetivo de producto

La app debe funcionar de forma totalmente autocontenida:

- sin Python
- sin descargas en runtime
- sin servidores
- sin apps auxiliares

## Herramientas y referencias profesionales

### Integrables directamente

- `ONNX Runtime` (MIT): inferencia local dentro de la app.
- `Vision` / `Core ML` (Apple): APIs nativas para distribucion macOS.
- `MediaPipe Face Landmarker` (`face_landmarker.task`, Apache 2.0): malla facial densa y blendshapes empaquetables en el bundle.
- `3DDFA_V2` (MIT, codigo): referencia principal para fitting 3DMM denso y estable.
- `UltraFace` / `FaceBoxes` (MIT / Apache-2.0): detectores faciales ONNX redistribuibles para el bundle.
- `ArcFace ResNet100 ONNX` (Apache-2.0): base redistribuible para embedding/regresion de identidad local.

### Referencias a replicar 1:1, no redistribuir tal cual

- `DECA`: referencia de separacion identidad/expresion/pose/iluminacion.
  - Restriccion: licencia no comercial del proyecto original.
  - Decision: replicar el enfoque, no redistribuir pesos originales.

- `FaceVerse`: referencia de cabeza completa, ojos, dientes, lengua y regresion de identidad.
  - El codigo puede servir como referencia, pero no se debe depender de datasets/pesos no redistribuibles.
  - Decision: replicar internamente la parte de identidad derivada.

## Decision de producto

### Se usa dentro de la app

- `ONNX Runtime`
- `MediaPipe` task bundle
- pipeline propio Swift/Metal
- modelos bundleados en `Resources/Models`
- detector facial ONNX compatible (`FaceBoxes` o `UltraFace`)
- embedding/regresion de identidad compatible (`ArcFace` o replica interna)

### Se replica internamente

- regresor de identidad estilo `DECA/FaceVerse`
- fitting de identidad derivada
- render facial multicapa pro

## Estado de implementacion en el repo

- Integrado `ONNX Runtime` en `VirtualFaceCam.xcodeproj`
- Creado `ProfessionalFacePipeline`
- Creado `ProfessionalModelAssetManager`
- Creado `ProfessionalModelInstaller`
- Creado manifest `Resources/Models/MODEL_BUNDLE_MANIFEST.json`
- La app ya funciona en modo `bundle-only` para modelos

## Siguiente hito tecnico real

1. Bundlear detector ONNX redistribuible (`FaceBoxes` o `UltraFace`).
2. Conectar fitting denso local (`3DDFA_V2` compatible o replica interna) a salida de landmarks/cabeza.
3. Integrar embedding/regresor de identidad (`ArcFace` bundleado o replica interna estilo `FaceVerse`).
4. Sustituir el fallback de `Vision` por la ruta profesional completa cuando los pesos existan en el bundle.
