#!/bin/bash
# deploy.sh — Déploie un fichier vers le repo GitHub Workout
# Usage : ./deploy.sh fichier.json "message de commit"
# ou    : ./deploy.sh  (mode interactif — cherche les fichiers récents dans Downloads)

REPO="$HOME/Documents/Workout"
DOWNLOADS="$HOME/Downloads/Claude/Routine artefacts"
KNOWN_FILES=("routine_alimentaire.json" "nutrition.html" "index.html" "routine_sport.json" "app_sport.html" "glossaire_exercices.json" "glossaire_mobilite.json" "phase2_tracker.html" "deploy.sh" "exercise_library.json" "programme_sport.json" "bfs_workouts_refactored.json" "mobility_workouts_refactored.json" "core_exercises_refactored.json" "build.py" "programme_complet.json" "vahva_unified_mapping.json" "base_nutritionnelle.json")

# Fichiers source qui déclenchent un rebuild de programme_complet.json
BUILD_SOURCES=("exercise_library.json" "programme_sport.json" "bfs_workouts_refactored.json" "mobility_workouts_refactored.json" "core_exercises_refactored.json")

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Mode avec arguments ---
if [ -n "$1" ]; then
    FILE="$1"
    MSG="${2:-Update $(basename "$FILE") $(date +%Y-%m-%d)}"
    
    if [ ! -f "$FILE" ]; then
        # Chercher dans Downloads
        if [ -f "$DOWNLOADS/$FILE" ]; then
            FILE="$DOWNLOADS/$FILE"
        else
            echo -e "${RED}✗ Fichier introuvable : $FILE${NC}"
            exit 1
        fi
    fi
    
    BASENAME=$(basename "$FILE")
    cp "$FILE" "$REPO/$BASENAME"
    cd "$REPO"

    # Rebuild programme_complet.json si le fichier est une source sport
    for src in "${BUILD_SOURCES[@]}"; do
        if [ "$BASENAME" = "$src" ]; then
            echo -e "${YELLOW}⚙ $BASENAME est une source sport → build.py...${NC}"
            python3 "$REPO/build.py" --out "$REPO/programme_complet.json"
            if [ $? -ne 0 ]; then
                echo -e "${RED}✗ build.py a échoué — déploiement annulé${NC}"
                exit 1
            fi
            git add "programme_complet.json"
            break
        fi
    done

    git add "$BASENAME"
    git commit -m "$MSG"
    git pull --rebase 2>/dev/null
    git push
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $BASENAME déployé avec succès${NC}"
    else
        echo -e "${RED}✗ Erreur lors du push${NC}"
        exit 1
    fi
    exit 0
fi

# --- Mode interactif ---
echo ""
echo "╔══════════════════════════════════╗"
echo "║     🥬 Deploy → GitHub Pages    ║"
echo "╚══════════════════════════════════╝"
echo ""

# Chercher les fichiers connus récents dans Downloads (< 24h)
FOUND=()
for f in "${KNOWN_FILES[@]}"; do
    MATCH=$(find "$DOWNLOADS" -name "$f" -mmin -1440 2>/dev/null | head -1)
    if [ -n "$MATCH" ]; then
        FOUND+=("$MATCH")
    fi
done

if [ ${#FOUND[@]} -eq 0 ]; then
    echo -e "${YELLOW}Aucun fichier récent trouvé dans le dossier artefacts${NC}"
    echo "Fichiers surveillés : ${KNOWN_FILES[*]}"
    echo ""
    echo "Usage : ./deploy.sh nom_du_fichier.json \"message de commit\""
    exit 0
fi

echo "Fichiers récents trouvés :"
echo ""
for i in "${!FOUND[@]}"; do
    BASENAME=$(basename "${FOUND[$i]}")
    MOD=$(stat -f "%Sm" -t "%d/%m %H:%M" "${FOUND[$i]}")
    SIZE=$(stat -f "%z" "${FOUND[$i]}" | awk '{printf "%.1f Ko", $1/1024}')
    
    # Comparer avec la version dans le repo
    if [ -f "$REPO/$BASENAME" ]; then
        if diff -q "${FOUND[$i]}" "$REPO/$BASENAME" > /dev/null 2>&1; then
            STATUS="identique"
        else
            STATUS="modifié"
        fi
    else
        STATUS="nouveau"
    fi
    
    echo -e "  $((i+1)). ${GREEN}$BASENAME${NC}  ($SIZE, $MOD) [$STATUS]"
done

echo ""
echo -e "Déployer ? ${YELLOW}[a]${NC}ll / numéro(s) séparés par espace / ${YELLOW}[n]${NC}on"
read -r CHOICE

if [ "$CHOICE" = "n" ]; then
    echo "Annulé."
    exit 0
fi

# Déterminer quels fichiers déployer
if [ "$CHOICE" = "a" ]; then
    DEPLOY=("${FOUND[@]}")
else
    DEPLOY=()
    for idx in $CHOICE; do
        DEPLOY+=("${FOUND[$((idx-1))]}")
    done
fi

# Copier, committer, pousser
cd "$REPO"
DEPLOYED=()
NEEDS_BUILD=false
for f in "${DEPLOY[@]}"; do
    BASENAME=$(basename "$f")
    cp "$f" "$REPO/$BASENAME"
    git add "$BASENAME"
    DEPLOYED+=("$BASENAME")
    # Vérifier si ce fichier est une source sport
    for src in "${BUILD_SOURCES[@]}"; do
        if [ "$BASENAME" = "$src" ]; then
            NEEDS_BUILD=true
            break
        fi
    done
done

# Rebuild programme_complet.json si au moins une source sport a changé
if [ "$NEEDS_BUILD" = true ]; then
    echo -e "${YELLOW}⚙ Source(s) sport modifiée(s) → build.py...${NC}"
    python3 "$REPO/build.py" --out "$REPO/programme_complet.json"
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ build.py a échoué — déploiement annulé${NC}"
        exit 1
    fi
    git add "programme_complet.json"
    DEPLOYED+=("programme_complet.json")
fi

FILES_STR=$(IFS=', '; echo "${DEPLOYED[*]}")
git commit -m "Update $FILES_STR $(date +%Y-%m-%d)"
git pull --rebase 2>/dev/null
git push

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Déployé : $FILES_STR${NC}"
    echo -e "  → https://tombychan.github.io/Workout/"
else
    echo -e "${RED}✗ Erreur lors du push${NC}"
fi
