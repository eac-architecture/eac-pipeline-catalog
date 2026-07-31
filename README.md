# EAC Pipeline Catalog

Catálogo versionado de Tasks, Pipelines y plantillas consumidoras para la
entrega de productos EAC mediante Tekton y Pipelines as Code.

El catálogo es un producto transversal independiente. No pertenece a
EAC.Foundation, a un servicio concreto ni a una solución funcional.

## Navegación

- [Índice documental](docs/INDICE_DOCUMENTAL.md)
- [Diseño del catálogo](docs/architecture/EAC_PIPELINE_CATALOG.md)
- [Plan de implementación](docs/planning/PLAN_DE_IMPLEMENTACION.md)

## Perfil disponible

| Perfil | Recurso | Estado |
|---|---|---|
| NuGet CI | `eac-nuget-ci` | Implementado |

## Instalación manual en Tekton

```bash
./scripts/install.sh
```

La instalación permite ejecutar las Pipelines directamente con `tkn`. Para
eventos Git, el repositorio consumidor referencia una versión inmutable del
catálogo desde un `PipelineRun` bajo `.tekton/`; Pipelines as Code resuelve la
Pipeline y sus Tasks sin copiarlas al repositorio consumidor.
