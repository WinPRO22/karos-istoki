# Karos: Istoki — Berneo
[Русский](README.md) · [English](README.en.md) · **Español**

Emulador de servidor para **Karos NHN EN CBT1 b1008 (14 de agosto de 2009)**.
Autor: [WinPRO22](https://github.com/WinPRO22). [Noticias](https://t.me/karos_istoki).

Publicamos una etapa de desarrollo cerrada: **solo Berneo, con progresión hasta
el nivel 45**. El código permite que la comunidad continúe el trabajo.
Es una versión local para un jugador, no un servidor MMO listo para producción.

## Contenido
- Acceso, creación de personajes y guardado.
- 955 criaturas, 29 NPC, 16 tiendas y 41 misiones activadas en Berneo.
- Combate, agresividad, reaparición, equipo, experiencia, profesiones y habilidades.
- Inventario, botín, comercio, almacén, piedra de retorno, Fletta, fabricación y mejoras.
- Parches propios: acciones con clic derecho, confirmación con Enter,
  intercambio de habilidades y filas de la barra rápida, correcciones de efectos
  y estados de combate.

El espadachín y sus profesiones son las ramas más desarrolladas. La existencia de
un controlador no implica que se hayan probado todas las combinaciones.
El equilibrio incluye fórmulas propias. Otros mapas, investigaciones privadas
y el nuevo motor no forman parte de esta publicación.

## Descargar y jugar
Descarga **ambos ZIP** de [Releases](https://github.com/WinPRO22/karos-istoki/releases):
el cliente b1008 y el emulador Win64. Los binarios no requieren Delphi.

1. Extrae el emulador en una carpeta con permiso de escritura, por ejemplo
   `C:\Games\KarosIstoki`.
2. Extrae el cliente junto a él; debe quedar `client\AMo.exe`.
3. Abre PowerShell en la carpeta del emulador y ejecuta:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Start-Berneo.ps1 -ClientDirectory .\client`
4. Usa el usuario de demostración **test** y la contraseña **test**. Crea un
   personaje nuevo; no se incluye la partida del desarrollador.
5. Tras cerrar el juego, detén el servidor:
   `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Stop-Berneo.ps1`

El servidor escucha únicamente en `127.0.0.1:10001`. No abras ese puerto a
Internet ni cambies el cortafuegos. Las tasas y la velocidad predeterminadas son
**×1**. No mezcles el cliente con actualizadores ni recursos de otra versión.

## Compilación y datos
Se necesita Windows x64 y Delphi con compilador Win64, VCL, Indy y FireDAC.
Se utiliza Delphi 37.0 para preparar esta versión. Añade `dcc64.exe` al PATH y
ejecuta `.\ServerEmulator\Build.ps1` desde la raíz del repositorio.
Compila los programas y ejecuta las pruebas públicas autónomas, sin iniciar el
juego. La opción `-SkipTests` solo compila.

Los catálogos están en `ServerEmulator/data/b1008`. Las partidas se crean allí
como `test-character.b1008*`; la base de contenido es
`ServerEmulator/data/karos-emulator.sqlite3`. Haz una copia de seguridad con el
servidor detenido antes de actualizar. No sobrescribas tus partidas.

Guía para desarrolladores y agentes de IA:
[SKILL.md](skills/karos-berneo-development/SKILL.md).
Las pruebas públicas no necesitan archivos privados ni sustituyen las pruebas
en el juego. Antes de publicar se realiza una prueba manual del conjunto
distribuido; el resultado se indica en la descripción de la versión.

## Licencia
El código y las herramientas propios usan [MIT](LICENSE), conservando la
atribución a **WinPRO22**. MIT no cubre el cliente original ni sus recursos.
Consulta los [avisos de terceros](THIRD_PARTY_NOTICES.md). Proyecto no oficial.
