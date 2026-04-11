#!/bin/bash
# deploy.sh — Déploie un fichier vers le repo GitHub Workout
# Usage : ./deploy.sh fichier.json "message de commit"
# ou    : ./deploy.sh  (mode interactif — cherche les fichiers récents dans Downloads)

REPO="$HOME/Documents/Workout"
DOWNLOADS="$HOME/Downloads/Claude/Routine artefacts"
KNOWN_FILES=("routine_alimentaire.json" "base_nutritionnelle.json" "nutrition.html" "index.html" "app_sport.html" "sport.html" "flocons.html" "tempeh.html" "fermentation.html" "exercise_library.json" "programme_sport.json" "bfs_workouts_refactored.json" "mobility_workouts_refactored.json" "core_exercises_refactored.json" "programme_complet.json" "vahva_unified_mapping.json" "flow_library.json" "flow_library.md" "programme_synthese_v3.md" "fermentation_index.json" "houmous_gaba.json" "flocons_fermentes.json" "tempeh.json" "build.py" "deploy.sh")

# Mapping : basename → chemin relatif dans le repo
declare -A FILE_MAP=(
  ["routine_alimentaire.json"]="data/nutrition/"
  ["base_nutritionnelle.json"]="data/nutrition/"
  ["exercise_library.json"]="data/sport/"
  ["programme_sport.json"]="data/sport/"
  ["bfs_workouts_refactored.json"]="data/sport/"
  ["mobility_workouts_refactored.json"]="data/sport/"
  ["core_exercises_refactored.json"]="data/sport/"
  ["programme_complet.json"]="data/sport/"
  ["vahva_unified_mapping.json"]="data/sport/"
  ["flow_library.json"]="data/sport/"
  ["flow_library.md"]="data/sport/"
  ["programme_synthese_v3.md"]="data/sport/"
  ["fermentation_index.json"]="data/fermentation/"
  ["houmous_gaba.json"]="data/fermentation/"
  ["flocons_fermentes.json"]="data/fermentation/"
  ["tempeh.json"]="data/fermentation/"
  ["build.py"]="scripts/"
  ["deploy.sh"]="scripts/"
)

# Résout le chemin repo pour un basename (racine si pas dans FILE_MAP)
repo_path() {
  local dir="${FILE_MAP[$1]}"
  if [ -n "$dir" ]; then echo "$dir$1"; else echo "$1"; fi
}

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
    DEST=$(repo_path "$BASENAME")
    cp "$FILE" "$REPO/$DEST"
    cd "$REPO"

    # Rebuild programme_complet.json si le fichier est une source sport
    for src in "${BUILD_SOURCES[@]}"; do
        if [ "$BASENAME" = "$src" ]; then
            echo -e "${YELLOW}⚙ $BASENAME est une source sport → build.py...${NC}"
            python3 "$REPO/scripts/build.py" --out "$REPO/data/sport/programme_complet.json"
            if [ $? -ne 0 ]; then
                echo -e "${RED}✗ build.py a échoué — déploiement annulé${NC}"
                exit 1
            fi
            git add "data/sport/programme_complet.json"
            break
        fi
    done

    git add "$DEST"
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
    DEST=$(repo_path "$BASENAME")
    if [ -f "$REPO/$DEST" ]; then
        if diff -q "${FOUND[$i]}" "$REPO/$DEST" > /dev/null 2>&1; then
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
    DEST=$(repo_path "$BASENAME")
    cp "$f" "$REPO/$DEST"
    git add "$DEST"
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
    python3 "$REPO/scripts/build.py" --out "$REPO/data/sport/programme_complet.json"
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ build.py a échoué — déploiement annulé${NC}"
        exit 1
    fi
    git add "data/sport/programme_complet.json"
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
