#!/bin/sh
# Copies the app screenshots from docs/ into public/shots for the film.
set -e
cd "$(dirname "$0")/.."
mkdir -p public/shots
cp ../../docs/design/01-popup.png ../../docs/design/11-big-linker.png ../../docs/design/12-big-photobook.png \
   ../../docs/design/13-big-full.png ../../docs/design/14-big-notepad-quotes.png ../../docs/design/16-big-dark.png \
   ../../docs/design/21-recent-copies.png ../../docs/images/canvas.png public/shots/
