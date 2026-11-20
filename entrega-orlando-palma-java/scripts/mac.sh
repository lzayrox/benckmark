#!/usr/bin/env bash
# Utilidades de macOS para las corridas: abrir terminales auxiliares, colocar
# ventanas en posiciones fijas, hacer clic y tomar capturas.
#
# Se carga con:  source scripts/mac.sh
#
# Requisitos: screencapture y osascript (vienen con macOS) y cliclick
# (brew install cliclick) para los clics en la GUI de JMeter.
#
# La primera vez que se ejecuta screencapture, macOS pide permiso de
# "Grabacion de pantalla" para la aplicacion desde la que se lanza el script.

set -uo pipefail

# ---------------------------------------------------------------- resolucion --
# Tamano de la pantalla principal, en puntos (lo que usan osascript y cliclick).
mac_screen_size() {
  osascript -e 'tell application "Finder" to get bounds of window of desktop' \
    | awk -F', *' '{print $3" "$4}'
}

# ------------------------------------------------------------------ ventanas --
# Trae al frente un proceso por nombre. Se usa System Events y no
# "tell application", porque el proceso de JMeter se llama "java" y no es
# una aplicacion a la que se le pueda hablar por nombre.
mac_activate() {
  osascript -e 'with timeout of 10 seconds' \
            -e "tell application \"System Events\" to set frontmost of process \"$1\" to true" \
            -e 'end timeout' >/dev/null 2>&1
}

# Coloca la ventana 1 de una app en x y con ancho y alto dados.
#   mac_place "Terminal" 0 0 900 500
mac_place() {
  local app="$1" x="$2" y="$3" w="$4" h="$5"
  osascript <<OSA >/dev/null 2>&1
tell application "System Events"
  tell process "$app"
    if (count of windows) > 0 then
      set position of window 1 to {$x, $y}
      set size of window 1 to {$w, $h}
    end if
  end tell
end tell
OSA
}

# Coloca una ventana concreta de un proceso, por indice.
#   mac_place_index Terminal 1 0 0 700 330
mac_place_index() {
  local app="$1" idx="$2" x="$3" y="$4" w="$5" h="$6"
  osascript <<OSA >/dev/null 2>&1
with timeout of 15 seconds
  tell application "System Events"
    tell process "$app"
      if (count of windows) >= $idx then
        set position of window $idx to {$x, $y}
        set size of window $idx to {$w, $h}
      end if
    end tell
  end tell
end timeout
OSA
}

# Imprime "x y w h" de la ventana MAS GRANDE de un proceso.
#
# Se busca la mayor y no la primera porque JMeter crea ventanas diminutas y
# efimeras para los tooltips: si justo coincide con la captura, "window 1" es
# el tooltip y la imagen sale de unos pocos pixeles.
mac_bounds() {
  osascript <<OSA 2>/dev/null
with timeout of 15 seconds
  tell application "System Events"
    tell process "$1"
      set bestArea to -1
      set best to {}
      repeat with w in windows
        try
          set p to position of w
          set s to size of w
          set a to (item 1 of s) * (item 2 of s)
          if a > bestArea then
            set bestArea to a
            set best to {item 1 of p, item 2 of p, item 1 of s, item 2 of s}
          end if
        end try
      end repeat
      if bestArea < 0 then return ""
      return (item 1 of best as text) & " " & (item 2 of best as text) & " " & (item 3 of best as text) & " " & (item 4 of best as text)
    end tell
  end tell
end timeout
OSA
}

# Espera hasta que exista una ventana del proceso dado (o se agote el tiempo).
#   mac_wait_window java 60
mac_wait_window() {
  local proc="$1" timeout="${2:-60}" i=0
  while [ "$i" -lt "$timeout" ]; do
    if [ -n "$(mac_bounds "$proc")" ]; then return 0; fi
    sleep 1; i=$((i + 1))
  done
  return 1
}

# ---------------------------------------------------------------- terminales --
# Abre una ventana nueva de Terminal.app ejecutando un comando.
mac_open_terminal() {
  osascript -e "tell application \"Terminal\" to do script \"$1\"" >/dev/null 2>&1
}

# Cierra todas las ventanas de Terminal cuyo comando contenga el texto dado.
mac_close_terminals_matching() {
  osascript <<OSA >/dev/null 2>&1
tell application "Terminal"
  repeat with w in windows
    try
      if (history of selected tab of w) contains "$1" then close w saving no
    end try
  end repeat
end tell
OSA
}

# ------------------------------------------------------------------ capturas --
# Captura toda la pantalla principal.
#   mac_shot_screen salida.png
mac_shot_screen() {
  screencapture -x -D 1 "$1"
}

# Captura una region.
#   mac_shot_region x y w h salida.png
mac_shot_region() {
  screencapture -x -R "$1,$2,$3,$4" "$5"
}

# Captura la ventana 1 de un proceso, recortando por sus limites reales.
#   mac_shot_window java salida.png
mac_shot_window() {
  local proc="$1" out="$2" b
  b="$(mac_bounds "$proc")"
  if [ -z "$b" ]; then
    echo "  aviso: no se encontro ventana de '$proc', se captura la pantalla completa" >&2
    mac_shot_screen "$out"
    return
  fi
  # shellcheck disable=SC2086
  set -- $b
  mac_shot_region "$1" "$2" "$3" "$4" "$out"
}

# --------------------------------------------------------------------- clics --
# Clic en coordenadas absolutas.
#
# Se usa System Events, porque macOS concede el permiso de Accesibilidad a la
# aplicacion que lanza el script y no a un binario suelto: cliclick, al ser un
# ejecutable aparte, queda sin permiso y sus clics no llegan a ninguna parte.
# Si aun asi cliclick esta autorizado, se usa como alternativa.
mac_click() {
  if osascript -e 'with timeout of 10 seconds' \
                -e "tell application \"System Events\" to click at {$1, $2}" \
                -e 'end timeout' >/dev/null 2>&1; then
    return 0
  fi
  if command -v cliclick >/dev/null 2>&1 && cliclick -r "c:$1,$2" >/dev/null 2>&1; then
    return 0
  fi
  echo "  aviso: no se pudo hacer clic en ($1,$2)" >&2
  return 1
}

# Atajo de teclado a la app en primer plano, por ejemplo: mac_key r command
mac_key() {
  local key="$1" mods="${2:-}"
  if [ -n "$mods" ]; then
    osascript -e "tell application \"System Events\" to keystroke \"$key\" using {${mods} down}" >/dev/null 2>&1
  else
    osascript -e "tell application \"System Events\" to keystroke \"$key\"" >/dev/null 2>&1
  fi
}
