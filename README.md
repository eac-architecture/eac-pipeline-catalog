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
| NuGet release candidate | `eac-nuget-release-candidate` | Implementado sin publicación |
| NuGet prerelease publication | `eac-nuget-prerelease-publication` | Implementado con rama `release/*` y tag inmutable |
| NuGet stable publication | `eac-nuget-stable-publication` | Implementado con `main`, tag estable y confirmación `Listed` |

## Instalación manual en Tekton

```bash
./scripts/install.sh
```

La instalación permite ejecutar las Pipelines directamente con `tkn`. Para
eventos Git, el repositorio consumidor referencia una versión inmutable del
catálogo desde un `PipelineRun` bajo `.tekton/`; Pipelines as Code resuelve la
Pipeline y sus Tasks sin copiarlas al repositorio consumidor.

## Ejecución manual de CI

```bash
./scripts/run-ci.sh \
  https://github.com/eac-architecture/eac-foundation.git \
  main
```

El comando crea un `PipelineRun` con workspace efímero, muestra los logs y
devuelve un código distinto de cero cuando falla la ejecución. La Pipeline
`eac-nuget-ci` debe haberse instalado previamente con `scripts/install.sh`.
Esta entrada manual utiliza el mismo contrato que el trigger Git, pero no
simula ni necesita un evento de GitHub.

## Ejecución manual de un candidato NuGet

```bash
./scripts/run-release-candidate.sh \
  https://github.com/eac-architecture/eac-foundation.git \
  main
```

El comando compila una sola vez en `Release`, ejecuta pruebas, genera
`.nupkg`, `.snupkg`, SBOM SPDX, hashes y evidencia, y verifica el paquete desde
un consumidor limpio. No recibe credenciales y no publica el candidato.
La versión se obtiene del archivo `VERSION` del commit solicitado; durante la
estabilización puede ser `alpha.N`, `beta.N` o `rc.N`.

La ejecución utiliza un único workspace persistente. El código, la caché y los
artefactos quedan aislados en subdirectorios del mismo PVC para que cada
`TaskRun` tenga como máximo un workspace escribible y sea compatible con los
modos de `coschedule` de Tekton.

## Publicación manual del prerelease aprobado

Desde una rama `release/*` limpia y sincronizada se utiliza un tag prerelease
inmutable que apunta exactamente al commit aprobado:

```bash
./scripts/run-prerelease-publication.sh \
  https://github.com/eac-architecture/eac-foundation.git \
  <commit-sha> \
  release/0.1.0 \
  v0.1.0-alpha.2
```

La Pipeline repite validación, compilación, pruebas y empaquetado antes de
publicar. Rechaza cualquier commit que no coincida simultáneamente con la rama
`release/*` remota y el tag indicado. Obtiene la credencial exclusivamente del
Secret `eac-release-publishing`, clave
`nuget-api-key`, dentro de `eac-cicd`.
La ejecución solo termina correctamente cuando la Registration API confirma
que la versión exacta está `Listed`; la espera de indexación está limitada a
20 minutos.

## Publicación manual de la versión estable

Después de aceptar `release/X.Y.Z` en `main`, el tag `vX.Y.Z` debe apuntar al
commit exacto de `main`:

```bash
./scripts/run-stable-publication.sh \
  https://github.com/eac-architecture/eac-foundation.git \
  <main-commit-sha> \
  main \
  v0.1.0 \
  <final-candidate-pipelinerun> \
  <candidate-commit-sha> \
  EAC.Foundation.0.1.0.nupkg \
  <package-sha256> \
  EAC.Foundation.0.1.0.snupkg \
  <sbom-sha256> \
  evidence/release-evidence.json
```

La Pipeline rechaza versiones con sufijo, tags que no coincidan con `VERSION`,
commits distintos de `origin/main`, árboles fuente diferentes al candidato o
evidencias y hashes alterados. Reutiliza el workspace persistente del candidato
final y publica el `.nupkg` exacto ya construido, probado y verificado antes del
merge; no recompila desde `main`. EAC Platform Console resuelve normalmente
estos parámetros desde el `PipelineRun`, crea el GitHub Release y orquesta la
sincronización posterior de ramas.

No se debe ejecutar `scripts/clean.sh` entre el candidato final y su promoción:
la limpieza elimina el PVC retenido y obliga a generar otro candidato antes de
abrir o fusionar el pull request.

## Limpieza del namespace de ejecución

```bash
./scripts/clean.sh --confirm
```

La limpieza elimina las Tasks, Pipelines, ejecuciones, volúmenes efímeros y
registros `Repository` existentes en `eac-cicd`. Conserva la instalación base
de Tekton y Pipelines as Code, las credenciales y las Service Accounts; por
eso después se puede reinstalar el catálogo sin reconstruir la plataforma.
