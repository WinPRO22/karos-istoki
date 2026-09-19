# Karos: Истоки — de vuelta a Berneo

[Русский](README.md) · [English](README.en.md) · **Español**

**Investigamos los antiguos clientes de Karos y devolvemos la vida al juego de sus primeros años, mecánica a mecánica.**

¿Recuerdas las primeras arañas cerca de Berneo, tu espada inicial y tus primeros puntos de Fletta? Queremos recorrer ese camino de nuevo: partir de un cliente de 2009, conservar su atmósfera y reconstruir poco a poco sus mecánicas.

> 📣 **Sigue el desarrollo: [t.me/karos_istoki](https://t.me/karos_istoki)**
>
> Novedades del proyecto, resultados de las pruebas y descubrimientos en versiones antiguas.

## Sobre el proyecto

Karos: Истоки («Orígenes») es un proyecto independiente de aficionados que investiga las versiones antiguas de Karos y desarrolla un emulador de servidor para ellas.

Nuestro punto de partida es **NHN EN CBT1, versión b1008, de 2009**. Empezamos con una pequeña parte jugable, la probamos en el cliente original y ampliamos sus posibilidades paso a paso.

El servidor está escrito en **Delphi**. Por ahora, las pruebas se realizan en un entorno local. Este repositorio es la página pública de presentación del proyecto, no una versión del servidor lista para descargar y ejecutar.

## Qué funciona actualmente

- **Acceso al juego:** inicio de sesión, creación y selección de personajes y entrada al mundo.
- **Un Berneo más vivo:** 101 arañas pequeñas distribuidas por el mapa, con patrullas independientes, persecución, regreso a su territorio, combate en grupo y reaparición.
- **Combate:** ataques automáticos, animaciones, sonidos, cifras de daño, rangos de daño según el arma y golpes críticos.
- **Atributos y equipo:** estadísticas y equipo iniciales, equipar y desequipar objetos y actualización de los valores mostrados.
- **Inventario y botín:** los objetos aparecen al morir el monstruo; funcionan la recogida, el movimiento y el lanzamiento al suelo, la división de pilas con Shift y la combinación de pilas del mismo objeto.
- **Carats:** presentes tanto como objeto en el inventario como en el saldo de la interfaz; ambas representaciones se actualizan al recogerlos o tirarlos.
- **Progresión del personaje:** experiencia por derrotar monstruos, subida de nivel, primera misión con recompensa y uso de pociones iniciales.
- **Muerte y recuperación:** regreso a la Piedra de la Memoria, penalización de experiencia y regeneración fuera del combate y de la postura de combate.
- **Guardado:** el progreso, el contenido y la posición de los objetos en el inventario y el equipo se conservan entre reinicios.

Estas funciones están implementadas en un prototipo local. El mundo completo, todo su contenido y la estabilidad multijugador siguen siendo objetivos pendientes.

## Cómo reconstruimos el equilibrio del juego

Comparamos recursos del cliente, sitios web archivados, guías antiguas, capturas, vídeos y recuerdos de los jugadores.

Separamos los valores confirmados de las estimaciones. Cuando desconocemos una fórmula del servidor original, utilizamos una reconstrucción provisional y la probamos en el juego. Algunos parámetros proceden de versiones posteriores y no se presentan como datos confirmados de CBT1.

Todavía no afirmamos un porcentaje de coincidencia con el equilibrio original. Por ejemplo, el botín de prueba actual aún debe sustituirse por tablas respaldadas por fuentes históricas.

## Hoja de ruta

1. **Investigar las versiones antiguas.** Comparar versiones, mecánicas, historia y recursos; buscar rastros de contenido no utilizado.
2. **Ampliar el prototipo jugable.** Desarrollar el combate, las misiones, los monstruos, los objetos, las habilidades, Fletta y la economía.
3. **Dar soporte a otros clientes antiguos.** Conservar las diferencias entre versiones mediante perfiles separados de protocolo y datos.
4. **Preparar una prueba pública.** Recoger comentarios y probar el servidor y el cliente con varios jugadores.
5. **Optimizar el servidor.** Comprobar su comportamiento bajo carga, su estabilidad y la conservación de los datos.
6. **Publicar el código fuente del emulador en GitHub.** Preparar instrucciones detalladas para compilar, configurar y ejecutar un servidor propio.
7. **Sentar las bases de un futuro remake.** Reunir la investigación y las opiniones de los jugadores y después planificar una versión en otro motor, cercana a las mecánicas originales y abierta a nuevas posibilidades.

Los avances dependen de la investigación y de los resultados de las pruebas. Aún no se ha anunciado una fecha de lanzamiento público.

## Cómo ayudar

Nos resultan especialmente útiles los materiales de los primeros años de Karos:

- capturas de atributos, objetos, recompensas de misiones e interfaz;
- vídeos de combate, progresión, comercio, fabricación de objetos y otras mecánicas;
- enlaces a guías antiguas, foros y páginas archivadas;
- recuerdos de una versión concreta: ritmo de progresión, botín, comportamiento de los monstruos y diferencias entre clases.

Si es posible, indica el año, la región, el idioma o el número de versión. Así evitamos mezclar datos de distintas etapas del juego.

**Sigue el [canal de Telegram](https://t.me/karos_istoki) para conocer la investigación y las novedades del proyecto.**

## ¿Ya se puede jugar?

Por ahora, el desarrollo y las pruebas son locales. Anunciaremos en Telegram cómo participar cuando se prepare una prueba pública.

## ¿Se publicará el código fuente?

Sí. Publicar el código fuente del emulador y las instrucciones de puesta en marcha forma parte del plan. De momento, este repositorio presenta el proyecto y enlaza a las novedades del desarrollo.

---

Este proyecto no es oficial ni está vinculado a los desarrolladores o editores del juego original. Los nombres y los materiales originales del juego pertenecen a sus respectivos titulares de derechos.

**[Sigue el desarrollo en Telegram →](https://t.me/karos_istoki)**
