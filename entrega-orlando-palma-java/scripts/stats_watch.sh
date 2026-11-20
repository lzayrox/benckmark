#!/usr/bin/env bash
# Muestra docker stats en vivo de los contenedores dados, con las columnas
# reducidas a nombre, CPU y memoria, que es lo que se lee en las capturas.
#
# Existe como script aparte y no como una linea dentro de level.sh porque el
# formato lleva tabuladores y estos se pierden al pasar el comando por
# AppleScript hasta la terminal.
exec docker stats --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" "$@"
