# StickyDesk

Notas tipo post-it en el escritorio de macOS mediante un widget de WidgetKit, gestionadas desde una app de barra de menú, con importación (solo lectura) desde Recordatorios y un servidor MCP para que agentes de código creen y consulten notas.

- **StickyDeskApp**: app de barra de menú (`LSUIElement`). Notas, proyectos, importación de Recordatorios, ajustes.
- **StickyWidget**: widget transparente en tamaños small/medium/large.
- **stickydesk-mcp**: servidor MCP por stdio, incluido en `StickyDesk.app/Contents/Helpers/`.
- **StickyCore**: Swift Package local con todo el modelo, la persistencia, el merge y la lógica de agentes, con tests.

## Requisitos

| | Mínimo | Probado con |
|---|---|---|
| macOS (deployment target) | 14.0 | 27.2 |
| Xcode | **16.0** (Swift 6, Swift Testing) | 27.2 |
| XcodeGen | 2.38+ | 2.48.0 |

```bash
brew install xcodegen
```

## Build

```bash
xcodegen generate
```

```bash
open StickyDesk.xcodeproj
```

En Xcode elige el esquema **StickyDeskApp** y ejecútalo (⌘R). El `.xcodeproj` se genera a partir de `project.yml` y no se versiona; nunca lo edites a mano.

Desde la terminal:

```bash
xcodebuild -project StickyDesk.xcodeproj -scheme StickyDeskApp -configuration Debug -destination 'platform=macOS' -allowProvisioningUpdates build
```

> Si `xcode-select -p` apunta a `/Library/Developer/CommandLineTools`, `xcodebuild` falla. Ejecuta `sudo xcode-select -s /Applications/Xcode.app` o antepón `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` a cada comando.

### Tests

```bash
cd Packages/StickyCore && swift test
```

Cubren el merge, la persistencia (round-trip, archivo corrupto o inexistente, JSON antiguo), `tilt`, el borrado de proyectos, las herramientas MCP, los límites, el protocolo JSON-RPC, una sesión stdio real contra el binario y escrituras concurrentes entre procesos.

## Configuración: Team ID, bundle IDs y App Group

Todo se configura en `project.yml`:

| Ajuste | Valor actual |
|---|---|
| `DEVELOPMENT_TEAM` | `88X2SWBZJ8` (cámbialo por tu Team ID) |
| App | `com.jfzepeda.stickydesk` |
| Widget | `com.jfzepeda.stickydesk.widget` |
| MCP helper | `com.jfzepeda.stickydesk.mcp` |
| `STICKY_APP_GROUP` | `$(TeamIdentifierPrefix)stickydesk` → `88X2SWBZJ8.stickydesk` |

`STICKY_APP_GROUP` es la única fuente de verdad. XcodeGen lo escribe en los entitlements de los tres targets y en la clave `StickyAppGroupID` de cada `Info.plist`, y `StickyCore` lee esa clave en tiempo de ejecución.

**¿Por qué el prefijo del Team ID y no `group.com.jfzepeda.stickydesk`?** En macOS 15+, los App Groups que empiezan con `group.` tienen que estar autorizados por un provisioning profile. Un ejecutable de línea de comandos (el helper MCP) no puede incluir uno, así que el sistema mostraría el aviso "*quiere acceder a datos de otras apps*" o le negaría el acceso. Con `<TeamID>.<nombre>`, la firma con el Team ID basta, y así se verificó: el helper firmado y en sandbox lee y escribe el contenedor compartido sin avisos. Si prefieres el formato `group.` (y no usas el MCP), cambia la línea a `STICKY_APP_GROUP: group.com.jfzepeda.stickydesk`, regenera el proyecto y registra el grupo en tu cuenta de desarrollador.

Los datos viven en `~/Library/Group Containers/<STICKY_APP_GROUP>/StickyDesk/notes.json`, junto a `notes.lock`.

## Añadir el widget al escritorio

1. Ejecuta la app al menos una vez (aparece el icono 🗒 en la barra de menú).
2. Haz clic derecho en el escritorio → **Editar widgets…**
3. Busca **StickyDesk**, elige el tamaño y arrástralo al escritorio.

Con 0 notas, el widget muestra una hoja de libreta que dice "Sin notas". Con notas, muestra post-its: vainilla, o con el color del proyecto y su nombre abajo a la derecha. Al hacer clic en una nota se abre en la app (`stickydesk://note/<uuid>`).

## Importar desde Recordatorios

Pestaña **Recordatorios** → *Permitir acceso*. Elige las listas (por defecto no hay ninguna seleccionada) → *Importar ahora*.

- Cada lista se convierte en un proyecto con su nombre y color. Si después editas el proyecto, la importación no sobrescribe tus cambios.
- Solo se importan los recordatorios **pendientes**. La importación es unidireccional y nunca escribe en Recordatorios.
- *Limpiar huérfanas* borra las notas importadas que ya no aparecen (completadas o eliminadas). Las notas manuales nunca se tocan.
- Mientras la app está abierta, se reimporta automáticamente cuando cambian tus Recordatorios.
- Si denegaste el permiso: **Ajustes del Sistema → Privacidad y seguridad → Recordatorios** y activa StickyDesk.

## Servidor MCP (`stickydesk-mcp`)

El binario se compila con la app y se copia firmado en `StickyDesk.app/Contents/Helpers/stickydesk-mcp`. En **Ajustes → Agentes** de la app tienes los botones **Copiar configuración para Claude Code** y **Copiar configuración para Claude Desktop**.

Claude Code:

```bash
claude mcp add stickydesk -- '/Applications/StickyDesk.app/Contents/Helpers/stickydesk-mcp'
```

Claude Desktop (`claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "stickydesk": {
      "command": "/Applications/StickyDesk.app/Contents/Helpers/stickydesk-mcp",
      "args": []
    }
  }
}
```

Para probarlo con MCP Inspector:

```bash
npx @modelcontextprotocol/inspector /Applications/StickyDesk.app/Contents/Helpers/stickydesk-mcp
```

### Herramientas

| Herramienta | Qué hace |
|---|---|
| `create_note` | `text` (1–500), `project` opcional (sin distinguir mayúsculas), `create_project_if_missing` (por defecto `false`), `idempotency_key`. Devuelve `id`, `text`, `project`. |
| `list_projects` | Nombre y color en hex. Solo lectura. |
| `list_notes` | `project` y `limit` opcionales (1–50, por defecto 20). Solo lectura. |
| `delete_note` | Solo notas con `createdBy == "agent"`. Las demás devuelven un error de permisos. |

Seguridad: todo lo que llega de un agente se valida (tipos exactos, longitudes, sin parámetros desconocidos), se eliminan los caracteres de control y bidi, y se rechaza el texto vacío. Hay un límite de **30 notas por minuto** y un tope de **200 notas de agentes**; los dos se guardan en el store, así que valen entre procesos. El helper corre en **sandbox y sin entitlement de red**, y no ejecuta comandos. Las notas de agentes llevan un icono 🖥 en la lista de la app. En Ajustes puedes desactivar "Permitir notas de agentes" o borrarlas todas.

## Limitaciones conocidas

- **Un widget no puede añadirse, moverse ni quitarse desde código**: el usuario lo coloca a mano.
- **El widget reserva su espacio** en la grilla aunque sea transparente.
- **El refresco del widget lo gobierna el sistema** y no es en tiempo real. La app llama a `reloadAllTimelines()` después de cada cambio, y el timeline se renueva cada 30 minutos como respaldo.
- **No se puede editar ni arrastrar dentro del widget**: la edición ocurre en la app.
- **El sistema puede desaturar o teñir el widget** según el estilo que elija el usuario. En modo *accented* las notas llevan un borde fino para distinguirlas.
- **Refresco tras escrituras del MCP**: el helper publica una notificación Darwin (`com.jfzepeda.stickydesk.store-changed`). Si la app está abierta, recarga y pide el refresco del widget al momento. El helper también llama a `reloadAllTimelines()`, pero desde un proceso de línea de comandos sin bundle de app **no está comprobado** que WidgetKit le haga caso. Si la app está cerrada, el widget puede tardar hasta el siguiente ciclo del timeline (≤ 30 min).
- **Override de ruta solo en Debug**: los builds Debug del helper aceptan `STICKYDESK_STORE_PATH` (lo usan los tests). En Release esa ruta no se compila.
