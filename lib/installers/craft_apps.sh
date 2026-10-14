#!/bin/bash
# Craft App Suite installer functions (PhotoCraft, VectorCraft, ...).
# Each app is a thin wrapper over the shared helpers in artcraft.sh.

# --- Craft apps ---

check_photocraft()       { _craft_check photocraft; }
install_photocraft()     { _craft_install photocraft photocraft "PhotoCraft"; }
uninstall_photocraft()   { _craft_uninstall photocraft "PhotoCraft"; }
update_photocraft()      { _craft_update photocraft photocraft "PhotoCraft"; }
get_version_photocraft() { _craft_version photocraft; }

check_vectorcraft()       { _craft_check vectorcraft; }
install_vectorcraft()     { _craft_install vectorcraft vectorcraft "VectorCraft"; }
uninstall_vectorcraft()   { _craft_uninstall vectorcraft "VectorCraft"; }
update_vectorcraft()      { _craft_update vectorcraft vectorcraft "VectorCraft"; }
get_version_vectorcraft() { _craft_version vectorcraft; }

check_filmcraft()       { _craft_check filmcraft; }
install_filmcraft()     { _craft_install filmcraft filmcraft "FilmCraft"; }
uninstall_filmcraft()   { _craft_uninstall filmcraft "FilmCraft"; }
update_filmcraft()      { _craft_update filmcraft filmcraft "FilmCraft"; }
get_version_filmcraft() { _craft_version filmcraft; }

check_lightcraft()       { _craft_check lightcraft; }
install_lightcraft()     { _craft_install lightcraft lightcraft "LightCraft"; }
uninstall_lightcraft()   { _craft_uninstall lightcraft "LightCraft"; }
update_lightcraft()      { _craft_update lightcraft lightcraft "LightCraft"; }
get_version_lightcraft() { _craft_version lightcraft; }

check_pdfcraft()       { _craft_check pdfcraft; }
install_pdfcraft()     { _craft_install pdfcraft pdfcraft "PdfCraft"; }
uninstall_pdfcraft()   { _craft_uninstall pdfcraft "PdfCraft"; }
update_pdfcraft()      { _craft_update pdfcraft pdfcraft "PdfCraft"; }
get_version_pdfcraft() { _craft_version pdfcraft; }

check_effectcraft()       { _craft_check effectcraft; }
install_effectcraft()     { _craft_install effectcraft effectcraft "EffectCraft"; }
uninstall_effectcraft()   { _craft_uninstall effectcraft "EffectCraft"; }
update_effectcraft()      { _craft_update effectcraft effectcraft "EffectCraft"; }
get_version_effectcraft() { _craft_version effectcraft; }

check_designcraft()       { _craft_check designcraft; }
install_designcraft()     { _craft_install designcraft designcraft "DesignCraft"; }
uninstall_designcraft()   { _craft_uninstall designcraft "DesignCraft"; }
update_designcraft()      { _craft_update designcraft designcraft "DesignCraft"; }
get_version_designcraft() { _craft_version designcraft; }

check_wordcraft()       { _craft_check wordcraft; }
install_wordcraft()     { _craft_install wordcraft wordcraft "WordCraft"; }
uninstall_wordcraft()   { _craft_uninstall wordcraft "WordCraft"; }
update_wordcraft()      { _craft_update wordcraft wordcraft "WordCraft"; }
get_version_wordcraft() { _craft_version wordcraft; }

check_deckcraft()       { _craft_check deckcraft; }
install_deckcraft()     { _craft_install deckcraft deckcraft "DeckCraft"; }
uninstall_deckcraft()   { _craft_uninstall deckcraft "DeckCraft"; }
update_deckcraft()      { _craft_update deckcraft deckcraft "DeckCraft"; }
get_version_deckcraft() { _craft_version deckcraft; }

check_gridcraft()       { _craft_check gridcraft; }
install_gridcraft()     { _craft_install gridcraft gridcraft "GridCraft"; }
uninstall_gridcraft()   { _craft_uninstall gridcraft "GridCraft"; }
update_gridcraft()      { _craft_update gridcraft gridcraft "GridCraft"; }
get_version_gridcraft() { _craft_version gridcraft; }

check_cadcraft()       { _craft_check cadcraft; }
install_cadcraft()     { _craft_install cadcraft cadcraft "CADCraft"; }
uninstall_cadcraft()   { _craft_uninstall cadcraft "CADCraft"; }
update_cadcraft()      { _craft_update cadcraft cadcraft "CADCraft"; }
get_version_cadcraft() { _craft_version cadcraft; }

check_soundcraft()       { _craft_check soundcraft; }
install_soundcraft()     { _craft_install soundcraft soundcraft "SoundCraft"; }
uninstall_soundcraft()   { _craft_uninstall soundcraft "SoundCraft"; }
update_soundcraft()      { _craft_update soundcraft soundcraft "SoundCraft"; }
get_version_soundcraft() { _craft_version soundcraft; }
