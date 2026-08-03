# Plan de implementación de EAC Pipeline Catalog

## 1. Objetivo

Implementar de forma incremental un catálogo reutilizable para todos los tipos
de producto de EAC Platform y sus soluciones consumidoras.

## 2. Incrementos

| ID | Alcance | Dependencia | Estado | Evidencia |
|---|---|---|---|---|
| PC-001 | identidad, estructura y contrato de consumo | ADR transversal | Completado | catálogo `0.1.0` publicado |
| PC-002 | perfil `packages/nuget` CI | PC-001 | En curso | ejecución manual aprobada; evento Git pendiente |
| PC-003A | candidato `packages/nuget` para G5-G7 | PC-002 | En curso | package, SBOM, smoke test y evidencia |
| PC-003B | publicación `packages/nuget` para G8 | PC-003A y credencial | Implementado; pendiente de ejecución | compuerta `release/*` + tag, Secret y publicación NuGet |
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

Ejecutar el flujo completo con EAC.Foundation: integrar cambios en `develop`,
preparar `release/0.1.0`, validar el candidato y publicar el prerelease mediante
un tag inmutable sobre esa rama. Solo la versión estable aprobada se fusionará
a `main`. La firma de paquetes se evaluará
como una decisión posterior independiente de la primera publicación.
