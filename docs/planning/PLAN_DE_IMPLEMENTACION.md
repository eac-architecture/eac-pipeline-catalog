# Plan de implementación de EAC Pipeline Catalog

## 1. Objetivo

Implementar de forma incremental un catálogo reutilizable para todos los tipos
de producto de EAC Platform y sus soluciones consumidoras.

## 2. Incrementos

| ID | Alcance | Dependencia | Estado | Evidencia |
|---|---|---|---|---|
| PC-001 | identidad, estructura y contrato de consumo | ADR transversal | Completado | catálogo `0.1.0` publicado |
| PC-002 | perfil `packages/nuget` CI | PC-001 | Completado | `v0.4.10` ejecuta Tasks .NET nativas, checkout privado aislado, eventos Pipelines as Code de PR/push y los perfiles opcionales `kafka`, `postgresql`, `mongodb` y `elasticsearch`; los consumidores mantienen bindings mínimos verificados |
| PC-002K | integración Kafka opcional en los pipelines NuGet reutilizables | PC-002 y consumidor Kafka real | Completado | selector `integration-profile: kafka` compartido por CI, candidato y prerelease; Task reutilizable con sidecar fijado y pruebas contra `KAFKA_BOOTSTRAP_SERVERS` |
| PC-002P | integración PostgreSQL opcional en los pipelines NuGet reutilizables | PC-002 y consumidor EF Core real | Completado | selector `integration-profile: postgresql` compartido por CI, candidato y prerelease; PipelineRun `eac-infrastructure-persistence-efcore-ci-zdppk` completó build sin warnings y 18/18 pruebas sobre PostgreSQL 17.6 mediante el sidecar no privilegiado |
| PC-002M | integración MongoDB opcional en los pipelines NuGet reutilizables | PC-002 y consumidor MongoDB real | Completado | selector `integration-profile: mongodb` compartido por CI, candidato y prerelease; `eac-nuget-ci-run-w8xzt` completó 37/37 pruebas sobre standalone y replica set efímeros no privilegiados |
| PC-002E | integración Elasticsearch opcional en los pipelines NuGet reutilizables | PC-002 y consumidor Elasticsearch real | Completado en `0.4.10` | `eac-infrastructure-search-elasticsearch-ci-cvf29` validó el commit integrado `2b238a2a4b567c9fc97c5387999e8b3d46e0e015`: build sin warnings y 17/17 pruebas contra Elasticsearch 9.3.4 no privilegiado mediante `integration-profile: elasticsearch` |
| PC-002R | resolución remota del perfil de integración | PC-002K, PC-002P y PC-002M | Completado | CI `eac-nuget-ci-run-n7vnt` y candidato `eac-nuget-release-candidate-run-pzspf` recibieron deliberadamente `default`, resolvieron `mongodb` desde el binding remoto y completaron 37/37 pruebas; prerelease usa la misma Task y las mismas condiciones antes de publicar |
| PC-003A | candidato `packages/nuget` para G5-G7 | PC-002 | Completado | `EAC.Foundation 0.1.0-rc.1`: package, símbolos, SBOM, smoke test y evidencia |
| PC-003B | publicación prerelease `packages/nuget` para G8 | revisión y tag de `release/*`, confirmación explícita y credencial | Completado | una `PipelineRun` ejecuta compuerta, build, pruebas, candidato y publicación; termina al aceptar el registro la identidad y no requiere candidato previo |
| PC-003C | promoción estable `packages/nuget` | PC-003B y merge aprobado a `main` | Implementado; ejecución real pendiente | candidato estable retenido antes del merge; compuerta de árbol, evidencia y hashes; publicación exacta sin recompilar; confirmación `Listed` |
| PC-003D | reproducibilidad byte a byte del candidato NuGet | PC-003A | Completado en `0.4.9` | `eac-nuget-release-candidate-run-8vs64` y `eac-nuget-release-candidate-run-6vtsr` reconstruyeron el commit `d1afcb26c12841d905a7fa671ec113676c78075c`; `.nupkg`, `.snupkg` y SPDX resultaron idénticos byte a byte; `test-reproducibility.py` reporta `EAC-PC-CANDIDATE-001` |
| PC-003E | directorios de ejecución escribibles para la normalización en Tekton | PC-003D y ejecución real | Completado en `0.4.9` | `TMPDIR`, `DOTNET_CLI_HOME` y `XDG_DATA_HOME` se crean dentro del workspace; el inventario SPDX `files` se ordena antes de persistir la evidencia |
| PC-003F | trazabilidad ejecutable del perfil NuGet implementado | PC-002 a PC-003E | Completado | `test-catalog-contracts.py` enlaza las reglas de catálogo, versión, CI, prerelease, stable, credenciales y validación con los manifiestos y scripts distribuidos; `validate.sh` rechaza metadatos ausentes |
| PC-004 | perfiles `packages/npm` | contrato npm | Implementado no publicado; ejecución integrada pendiente | SHA-256 transportado y revalidado justo antes de publicar, lifecycle scripts desactivados y prueba de mutación negativa; falta consumidor npm real, tag `v0.5.0` y publicación autorizada |
| PC-005 | perfiles `applications/angular` | PC-004 y contrato web | Implementado no publicado; ejecución integrada pendiente | doble build Production normalizado, imagen fijada por digest y `EAC-PC-ANGULAR-001`; falta consumidor Angular real y tag `v0.5.0` |
| PC-006 | perfiles `services/dotnet` | contrato de contenedor | Implementado no publicado; ejecución integrada pendiente | .NET SDK genera un archive retenido cuyo SHA-256 se revalida antes del login; Skopeo publica el mismo artifact y devuelve digest; falta consumidor real, GHCR autorizado y tag `v0.5.0` |
| PC-007 | perfil `deployments` | artifacts publicados | Implementado no publicado; ejecución integrada pendiente | endpoint, namespace, CA, allowlists y smoke son configuración confiable; sólo se promueven digest y workload autorizados, sin aplicar manifiestos no confiables ni interpolar parámetros en shell; falta target real y tag `v0.5.0` |
| PC-008 | integración con Service Starter | perfiles estables | Contrato implementado no publicado; generación externa pendiente | binding y PipelineRun templates conservan `__CATALOG_RELEASE_VERSION__` hasta existir el tag; los generation tests y la sustitución pertenecen a `eac-service-starter` |

La línea `0.4.9` corrige el directorio temporal de la normalización observado
en la primera ejecución real de `0.4.8` y conserva evidencia byte a byte de dos
candidatos completos. Los perfiles NuGet compartidos cubren CI,
candidato, publicación prerelease y preparación estable; `integration-profile`
selecciona únicamente el entorno adicional requerido por las pruebas sin crear
Pipelines específicas por componente.

La línea `0.4.10` añade únicamente la ruta opcional Elasticsearch al mismo
perfil NuGet. No crea una Pipeline por proveedor ni modifica bindings ajenos;
su cierre requiere una PipelineRun integrada del consumidor real.

La línea `0.5.0` está en preparación e incorpora como implementados no publicados los contratos de
npm, Angular, servicios .NET OCI y promoción por digest. El tag `v0.5.0` no
existe: las URLs y bindings conservan `__CATALOG_RELEASE_VERSION__` para impedir
que una implementación no publicada parezca consumible. La validación local
demuestra la estructura, el aislamiento de parámetros y credenciales, la
revalidación de SHA-256 y el pinning por digest de todas las imágenes ejecutadas
por Tasks. El plan conserva por separado la evidencia integrada que requiere consumidores,
credenciales o un destino OpenShift; no equipara una prueba de contrato con
una publicación o promoción real.

## 3. Regla de avance

No se cierra un perfil como `Completado` hasta validarlo con un consumidor
real. No se crean manifiestos vacíos ni perfiles especulativos. La
implementación contractual actualiza el catálogo, las plantillas, el diseño y
las pruebas; la ejecución integrada añade después la evidencia remota que no
puede simularse localmente.

## 4. Próximo resultado

Cuando exista autorización explícita, ejecutar con EAC.Foundation el cierre estable ya implementado: conservar el
candidato `0.1.0`, fusionar su árbol exacto desde `release/0.1.0`, crear
`v0.1.0`, promover sin recompilar el paquete retenido, confirmar `Listed`, crear
el GitHub Release y sincronizar `main` hacia `develop`. La firma de paquetes se
evaluará como una decisión posterior independiente.
