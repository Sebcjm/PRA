#!/bin/bash
# ============================================================
#  restore_www.sh - Déchiffrement + restauration de /var/www/html
# ============================================================

set -euo pipefail

# ---------- Configuration ----------
BACKUP_ROOT="/backup"
ARCHIVE_DIR="${BACKUP_ROOT}/archives"
KEY_DIR="${BACKUP_ROOT}/keys"
RESTORE_DIR="/var/www"                # Emplacement de restauration

# ---------- Vérifications ----------
[[ $EUID -eq 0 ]] || { echo "[ERREUR] Exécuter en root (sudo)." >&2; exit 1; }
command -v openssl >/dev/null || { echo "[ERREUR] openssl manquant." >&2; exit 1; }

# ---------- Menu : choix de l'archive ----------
clear
echo "============================================================"
echo "   Restauration de sauvegardes chiffrées"
echo "============================================================"
echo "Archives disponibles dans $ARCHIVE_DIR :"
echo

mapfile -t ARCHIVES < <(ls -1t "${ARCHIVE_DIR}"/*.tar.gz.enc 2>/dev/null || true)

if [[ ${#ARCHIVES[@]} -eq 0 ]]; then
    echo "Aucune archive trouvée."
    exit 1
fi

for i in "${!ARCHIVES[@]}"; do
    SIZE=$(du -h "${ARCHIVES[$i]}" | cut -f1)
    DATE=$(date -r "${ARCHIVES[$i]}" '+%Y-%m-%d %H:%M:%S')
    printf "  %2d) %-45s (%s, %s)\n" "$((i+1))" "$(basename "${ARCHIVES[$i]}")" "$SIZE" "$DATE"
done

echo
read -rp "Numéro de l'archive à restaurer (ou 'q' pour quitter) : " SEL
[[ "$SEL" == "q" ]] && exit 0
[[ "$SEL" =~ ^[0-9]+$ ]] && (( SEL >= 1 && SEL <= ${#ARCHIVES[@]} )) || {
    echo "Choix invalide."; exit 1;
}

ARCHIVE_ENC="${ARCHIVES[$((SEL-1))]}"
BASENAME=$(basename "$ARCHIVE_ENC" .tar.gz.enc)
KEY_FILE="${KEY_DIR}/${BASENAME}.key"
ARCHIVE_PLAIN="/tmp/${BASENAME}.tar.gz"

# ---------- Vérification de la clé ----------
if [[ -f "$KEY_FILE" ]]; then
    echo
    echo "Clé trouvée automatiquement : $KEY_FILE"
    read -rp "Utiliser cette clé ? [O/n] : " USE_KEY
    if [[ "${USE_KEY,,}" == "n" ]]; then
        KEY_FILE=""
    fi
fi

if [[ -z "${KEY_FILE:-}" || ! -f "$KEY_FILE" ]]; then
    echo
    echo "Entrez la clé de déchiffrement (collez la valeur base64) :"
    read -r MANUAL_KEY
    [[ -n "$MANUAL_KEY" ]] || { echo "Clé vide, abandon."; exit 1; }
    TMP_KEY=$(mktemp)
    echo "$MANUAL_KEY" > "$TMP_KEY"
    KEY_FILE="$TMP_KEY"
    CLEANUP_KEY=1
fi

# ---------- Déchiffrement ----------
echo
echo "Déchiffrement de l'archive..."
if ! openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
        -in "$ARCHIVE_ENC" -out "$ARCHIVE_PLAIN" -pass file:"$KEY_FILE"; then
    echo "[ERREUR] Échec du déchiffrement (mauvaise clé ?)." >&2
    rm -f "$ARCHIVE_PLAIN"
    [[ "${CLEANUP_KEY:-0}" -eq 1 ]] && rm -f "$KEY_FILE"
    exit 1
fi
echo "Déchiffrement OK -> $ARCHIVE_PLAIN"

# ---------- Choix de la destination ----------
echo
read -rp "Restaurer dans [$RESTORE_DIR] ? (Entrée = oui, sinon indiquez un chemin) : " DEST
DEST="${DEST:-$RESTORE_DIR}"

read -rp "ATTENTION : le dossier 'html' existant dans $DEST sera écrasé. Continuer ? [o/N] : " CONF
[[ "${CONF,,}" == "o" ]] || { echo "Annulé."; rm -f "$ARCHIVE_PLAIN"; exit 0; }

# ---------- Sauvegarde de l'existant ----------
if [[ -d "${DEST}/html" ]]; then
    SAFE="${DEST}/html.bak.$(date +%Y%m%d_%H%M%S)"
    echo "Sauvegarde de l'existant -> $SAFE"
    mv "${DEST}/html" "$SAFE"
fi

# ---------- Extraction ----------
mkdir -p "$DEST"
echo "Extraction dans $DEST ..."
tar -xzf "$ARCHIVE_PLAIN" -C "$DEST"

# ---------- Permissions correctes pour Apache ----------
if id www-data >/dev/null 2>&1; then
    chown -R www-data:www-data "${DEST}/html"
    find "${DEST}/html" -type d -exec chmod 755 {} \;
    find "${DEST}/html" -type f -exec chmod 644 {} \;
    echo "Permissions appliquées (www-data:www-data)."
fi

# ---------- Nettoyage ----------
rm -f "$ARCHIVE_PLAIN"
[[ "${CLEANUP_KEY:-0}" -eq 1 ]] && rm -f "$KEY_FILE"

echo
echo "=== Restauration terminée avec succès ==="
echo "Contenu restauré : ${DEST}/html"

Installation
bash

sudo cp restore_www.sh /usr/local/sbin/restore_www.sh
sudo chmod 700 /usr/local/sbin/restore_www.sh
sudo /usr/local/sbin/restore_www.sh

Détails importants
Élément	Choix	Pourquoi
Algorithme	AES-256-CBC + PBKDF2 (100 000 itérations)	Standard, robuste, dérivé du mot de passe sécurisé
Clé	32 octets aléatoires (openssl rand -base64 32)	256 bits d'entropie cryptographique
Nommage	Même BASENAME (horodaté) pour archive et clé	Association automatique à la restauration
Emplacement clé	/backup/keys/ en chmod 600	Accessible uniquement au root
Archive en clair	Supprimée immédiatement après chiffrement	Évite toute fuite sur disque
Option suppression clé	Menu 2	Utile si vous stockez la clé hors du serveur (coffre, gestionnaire)
Arborescence créée
text

/backup/
├── archives/
│   └── backup_www_html_20250115_143022.tar.gz.enc
├── keys/
│   └── backup_www_html_20250115_143022.key
└── logs/
    └── backup_www_html_20250115_143022.log

Exemple de cron (sauvegarde quotidienne à 2h)
bash

sudo crontab -e
# Ajouter :
0 2 * * * /usr/local/sbin/backup_www.sh --auto >/dev/null 2>&1
