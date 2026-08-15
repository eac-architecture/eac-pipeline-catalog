# Plan de implementación de EAC Pipeline Catalog

## 1. Objetivo

Implementar de forma incremental un catálogo reutilizable para todos los tipos
de producto de EAC Platform y sus soluciones consumidoras.

## 2. Incrementos

| ID | Alcance | Dependencia | Estado | Evidencia |
|---|---|---|---|---|
| PC-001 | identidad, estructura y contrato de consumo | ADR transversal | Completado | catálogo `0.1.0` publicado |
| PC-002 | perfil `packages/nuget` CI | PC-001 | En curso | ejecución manual aprobada; lectura Git privada aislada; contrato Bash uniforme y evento Git pendiente |
| PC-003A | candidato `packages/nuget` para G5-G7 | PC-002 | Completado | `EAC.Foundation 0.1.0-rc.1`: package, símbolos, SBOM, smoke test y evidencia |
| PC-003B | publicación prerelease `packages/nuget` para G8 | revisión y tag de `release/*`, confirmación explícita y credencial | Completado | una `PipelineRun` ejecuta compuerta, build, pruebas, candidato, publicación y confirmación `Listed`; no requiere candidato previo |
| PC-003C | promoción estable `packages/nuget` | PC-003B y merge aprobado a `main` | Implementado; ejecución real pendiente | candidato estable retenido antes del merge; compuerta de árbol, evidencia y hashes; publicación exacta sin recompilar; confirmación `Listed` |
| PC-003D | release estable `delivery/tekton-catalog` | commit aprobado en `main` | Implementado | Pipeline reutilizable valida versión y catálogo en Tekton y devuelve SHA, versión y estado antes del tag |
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

Ejecutar con EAC.Foundation el cierre estable ya implementado: conservar el
candidato `0.1.0`, fusionar su árbol exacto desde `release/0.1.0`, crear
`v0.1.0`, promover sin recompilar el paquete retenido, confirmar `Listed`, crear
el GitHub Release y sincronizar `main` hacia `develop`. La firma de paquetes se
evaluará como una decisión posterior independiente.
