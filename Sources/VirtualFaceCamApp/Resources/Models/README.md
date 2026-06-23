Bundle interno de modelos para `VirtualFaceCamApp`.

Objetivo:
- La app debe funcionar sin Python, sin descargas en runtime y sin herramientas externas.
- Todos los modelos finales deben empaquetarse en el bundle y copiarse a `Application Support` en el primer arranque.

Politica:
- `MediaPipe face_landmarker.task`: permitido para bundle interno (Apache 2.0).
- `3DDFA_V2` / `FaceBoxes`: usar pesos redistribuibles o replicas internas compatibles.
- `DECA`: no redistribuir dentro de una app comercial; replicar el pipeline 1:1 con modelo propio.
- `FaceVerse`: usar codigo/arquitectura como referencia; no depender de datasets o pesos no redistribuibles.

Archivos esperados por la app:
- `face_landmarker.task`
- `faceboxesv2-640x640.onnx`
- `3ddfa_mb05_bfm_head.onnx`
- `faceverse_resnet50_identity.onnx`

Mientras falten archivos, la app mostrara backend de fallback en la UI.
