#!/usr/bin/env python3
"""
build.py — Génère programme_complet.json depuis les fichiers source.

Usage :
    python3 build.py                  # output → programme_complet.json (répertoire courant)
    python3 build.py --check          # vérifie les libraryIds orphelins sans générer
    python3 build.py --out <path>     # output vers un chemin personnalisé

Workflow :
    Modifier les sources → python3 build.py → deploy.sh commit/push
    Ne jamais éditer programme_complet.json directement.
"""

import json
import sys
import os
from datetime import datetime
from pathlib import Path

# ── Configuration ─────────────────────────────────────────────────────────────
SOURCES = {
    "exercise_library":      "exercise_library.json",
    "bfs_workouts":          "bfs_workouts_refactored.json",
    "mobility_workouts":     "mobility_workouts_refactored.json",
    "core_exercises":        "core_exercises_refactored.json",
    "programme_sport":       "programme_sport.json",
}
OUTPUT = "programme_complet.json"


def load_sources(base_dir: Path) -> dict:
    """Charge tous les fichiers source."""
    data = {}
    for key, filename in SOURCES.items():
        path = base_dir / filename
        if not path.exists():
            print(f"  ❌ Fichier manquant : {path}")
            sys.exit(1)
        with open(path, encoding="utf-8") as f:
            data[key] = json.load(f)
        size = path.stat().st_size / 1024
        print(f"  ✅ {filename} ({size:.0f} KB)")
    return data


def build_exercise_index(library: dict) -> dict:
    """Index libraryId → exercise entry."""
    return library.get("exercises", {})


def resolve_exercise(ex: dict, index: dict) -> dict:
    """Enrichit un exercice de planning avec ses infos d'exécution."""
    lid = ex.get("libraryId")
    if not lid or lid not in index:
        return ex  # pas de résolution possible, retourner tel quel
    
    lib_entry = index[lid]
    resolved = dict(ex)  # copie du planning entry
    
    # Champs à injecter depuis la bibliothèque (si non déjà présents dans le planning)
    INJECT_FIELDS = [
        "name", "muscles_primaires", "muscles_secondaires", "equipment",
        "position_depart", "execution", "cue_principal", "erreurs_frequentes",
        "respiration", "notes_biomecaniques", "filtre_profil",
        "verdict", "asymmetry_note", "contra_indications", "video",
    ]
    
    for field in INJECT_FIELDS:
        # "label" dans le planning override "name" de la bibliothèque
        if field == "name" and resolved.get("label"):
            resolved["name"] = resolved.pop("label")
            continue
        if field not in resolved and lib_entry.get(field):
            resolved[field] = lib_entry[field]
    
    # Si pas de label override, utiliser le nom de la bibliothèque
    if "label" in resolved and not resolved.get("name"):
        resolved["name"] = resolved.pop("label")
    elif "label" in resolved:
        resolved.pop("label")  # label a déjà été traité
    
    return resolved


def check_orphans(data: dict, index: dict) -> list:
    """Trouve les libraryIds référencés dans le planning mais absents de la bibliothèque."""
    orphans = []
    semaine = data["programme_sport"].get("semaine", {})
    
    for jour, jour_data in semaine.items():
        for bloc in jour_data.get("blocs", []):
            for ex in bloc.get("exercises", []):
                lid = ex.get("libraryId")
                if lid and lid not in index:
                    orphans.append({
                        "jour": jour,
                        "bloc": bloc.get("id", "?"),
                        "libraryId": lid,
                        "label": ex.get("label") or ex.get("name", "?")
                    })
    return orphans


def build(base_dir: Path, output_path: Path, check_only: bool = False):
    print(f"\n{'='*55}")
    print(f"  build.py — {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*55}\n")
    
    print("Chargement des sources...")
    data = load_sources(base_dir)
    
    lib = data["exercise_library"]
    index = build_exercise_index(lib)
    print(f"\n  Bibliothèque : {len(index)} exercices")
    
    # ── Vérification des orphelins ────────────────────────────────────────────
    print("\nVérification des libraryIds...")
    orphans = check_orphans(data, index)
    if orphans:
        print(f"  ⚠️  {len(orphans)} libraryId(s) introuvable(s) dans exercise_library :")
        for o in orphans:
            print(f"     [{o['jour']} / {o['bloc']}] {o['libraryId']} ({o['label']})")
        if check_only:
            return
        print("  → Ces exercices seront inclus sans enrichissement bibliothèque.\n")
    else:
        print("  ✅ Tous les libraryIds résolus.\n")
    
    if check_only:
        print("Mode --check : aucun fichier généré.")
        return
    
    # ── Construction de programme_complet ─────────────────────────────────────
    print("Construction de programme_complet.json...")
    
    programme = data["programme_sport"]
    
    # Résoudre les exercices dans chaque bloc du planning
    semaine_resolue = {}
    for jour, jour_data in programme.get("semaine", {}).items():
        jour_resolue = dict(jour_data)
        blocs_resolus = []
        for bloc in jour_data.get("blocs", []):
            bloc_resolu = dict(bloc)
            if "exercises" in bloc:
                bloc_resolu["exercises"] = [
                    resolve_exercise(ex, index)
                    for ex in bloc["exercises"]
                ]
            blocs_resolus.append(bloc_resolu)
        jour_resolue["blocs"] = blocs_resolus
        semaine_resolue[jour] = jour_resolue
    
    # Assembler le fichier complet
    complet = {
        "meta": {
            "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            "generated_by": "build.py",
            "version": programme.get("meta", {}).get("version", "unknown"),
            "phase_active": programme.get("meta", {}).get("phase_active", "unknown"),
            "sources": {k: SOURCES[k] for k in SOURCES},
            "warning": "Fichier GÉNÉRÉ — ne pas éditer directement. Modifier les sources puis relancer build.py.",
        },
        "profil_biomecanique": programme.get("profil_biomecanique", {}),
        "regles_globales": programme.get("regles_globales", {}),
        "phases": programme.get("phases", {}),
        "semaine": semaine_resolue,
        "historique_routines": programme.get("historique_routines", []),
        "exercise_library": lib,
        "bfs_workouts": data["bfs_workouts"],
        "mobility_workouts": data["mobility_workouts"],
        "core_exercises": data["core_exercises"],
    }
    
    # ── Écriture ──────────────────────────────────────────────────────────────
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(complet, f, ensure_ascii=False, indent=2)
    
    size = output_path.stat().st_size / 1024
    print(f"  ✅ {output_path.name} — {size:.0f} KB")
    
    # ── Résumé ────────────────────────────────────────────────────────────────
    total_blocs = sum(
        len(j.get("blocs", []))
        for j in semaine_resolue.values()
    )
    total_ex_planning = sum(
        len(b.get("exercises", []))
        for j in semaine_resolue.values()
        for b in j.get("blocs", [])
    )
    print(f"\nRésumé :")
    print(f"  Jours planifiés      : {len(semaine_resolue)}")
    print(f"  Blocs totaux         : {total_blocs}")
    print(f"  Exercices planning   : {total_ex_planning}")
    print(f"  Exercices bibliothèque: {len(index)}")
    print(f"  Orphelins            : {len(orphans)}")
    print(f"\n✅ Build terminé → {output_path}\n")


if __name__ == "__main__":
    args = sys.argv[1:]
    check_only = "--check" in args
    
    # Determine output path
    output_path = Path(OUTPUT)
    if "--out" in args:
        idx = args.index("--out")
        if idx + 1 < len(args):
            output_path = Path(args[idx + 1])
    
    # Base dir = répertoire du script
    base_dir = Path(__file__).parent
    
    build(base_dir, output_path, check_only=check_only)
