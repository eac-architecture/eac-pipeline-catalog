# Plan de implementación de EAC Pipeline Catalog

## 1. Objetivo

Implementar de forma incremental un catálogo reutilizable para todos los tipos
de producto de EAC Platform y sus soluciones consumidoras.

## 2. Incrementos

| ID | Alcance | Dependencia | Estado | Evidencia |
|---|---|---|---|---|
| PC-001 | identidad, estructura y contrato de consumo | ADR transversal | En curso | diseño y catálogo validado |
| PC-002 | perfil `packages/nuget` CI | PC-001 | En curso | Foundation consume la Pipeline |
| PC-003 | perfil `packages/nuget` release | credenciales y gates G5-G8 | Pendiente | NuGet firmado y publicado |
| PC-004 | perfiles `packages/npm` | contrato npm | Pendiente | package probado y publicado |
| PC-005 | perfiles `applications/angular` | PC-004 y contrato OCI/web | Pendiente | aplicación web reproducible |
| PC-006 | perfiles `services/dotnet` | contrato de contenedor | Pendiente | imagen OCI por digest |
| PC-007 | perfil `deployments` | artifacts publicados | Pendiente | promoción sin recompilar |
| PC-008 | integración con Service Starter | perfiles estables | Pendiente | consumidores generados |

## 3. Regla de avance

Cada perfil se implementa primero con un consumidor real. No se crean
manifiestos vacíos ni perfiles especulativos. Al cerrar un incremento se
actualizan el catálogo, las plantillas, el diseño transversal y la evidencia.

## 4. Próximo resultado

Cerrar PC-001 y PC-002 usando EAC.Foundation como primer consumidor del perfil
`nuget-ci`. Después continuará la automatización por `pull_request` y
`push` mediante Pipelines as Code.
