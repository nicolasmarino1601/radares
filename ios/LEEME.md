# Radares para iPhone

Versión nativa del avisador de radares. Avisa aunque el teléfono esté bloqueado o tengas abierta otra
app (Google Maps, Waze, música). Si el iPhone está conectado al auto por Bluetooth o CarPlay, la voz
sale por los parlantes del auto y baja un momento el volumen de lo demás.

## Instalarla en tu iPhone (gratis, con tu Apple ID)

1. Instalá **Xcode** desde la App Store de la Mac y abrilo una vez (aceptá lo que te pida instalar).
2. En Xcode, menú **Integrate › Clone…** (o «Clone Git Repository…» en la ventana de bienvenida).
   Pegá `https://github.com/nicolasmarino1601/radares`, tocá **Clone** y elegí una carpeta.
3. Abrí el archivo **`ios/Radares.xcodeproj`** de esa carpeta.
4. **Xcode › Settings… › Accounts › «+» › Apple ID** y entrá con tu cuenta de Apple.
5. En la columna izquierda tocá **Radares** (el ícono azul de arriba) › pestaña **Signing & Capabilities**
   › **Team**: elegí «tu nombre (Personal Team)».
   Si aparece un error con el *Bundle Identifier*, agregale algo al final (por ejemplo `.nico`).
6. Conectá el iPhone a la Mac con el cable, desbloquealo y tocá **Confiar**.
   Arriba en Xcode elegí tu iPhone y tocá el botón **▶︎**.
7. Si el iPhone pide el **Modo de desarrollador**: Ajustes › Privacidad y seguridad › Modo de desarrollador ›
   activarlo (el teléfono se reinicia) y volvé a tocar ▶︎.
8. Si al abrir la app dice «Desarrollador no confiable»: Ajustes › General › VPN y gestión de dispositivos ›
   tu Apple ID › **Confiar**.
9. Abrí **Radares**, tocá **Iniciar** y permití la ubicación **«Mientras se usa la app»**.
   Para probarla sin manejar: Ajustes › «Probar sin manejar».

Con la cuenta gratuita de Apple la app vence a los **7 días**: conectá el iPhone y tocá ▶︎ otra vez.
Con el Apple Developer Program (99 USD al año) dura un año y se puede pasar por TestFlight o subir a la
App Store.

## Actualizarla

En Xcode: **Integrate › Pull**, y después ▶︎.

## Qué tiene

- Los mismos datos y el mismo motor de avisos que la versión web: radares fijos (por la carretera y en tu
  sentido de marcha), tramos de velocidad media con la media en vivo, tramos con radares móviles de la DGT,
  móviles anunciados y frecuentes, puntos de radar remolque y posibles radares sin confirmar.
- GPS y voz en segundo plano (modos `location` y `audio`).
- Mapa, lista ordenada por distancia, ajustes y simulaciones.
- Los datos se descargan al abrirla y se actualizan solos cada 6 horas; sin conexión usa los últimos guardados.

## Para desarrollo

- `Radares/` es el código (SwiftUI). `Geo.swift`, `RadarDB.swift` y `Engine.swift` no dependen de iOS.
- `Tests/main.swift` prueba el motor con los datos reales; lo corre GitHub Actions
  (`.github/workflows/ios.yml`), que además compila la app y saca capturas en el simulador
  (rama `ci-shots`).
