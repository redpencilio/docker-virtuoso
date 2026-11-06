#!/bin/bash
PROJECT_DIR=/project
DATA_DIR=data/db
FILES=(virtuoso.db virtuoso.trx virtuoso.pxa virtuoso-temp.db virtuoso-temp.trx virtuoso.lck)
MARKERS=(.config_set .dba_pwd_set .data_loaded .backup_restored)

if [[ ! -d "$PROJECT_DIR/$DATA_DIR" ]]; then
    echo ""
    echo "ERROR: $DATA_DIR does not exist"
    exit 1
fi

REMOVE_FILES=("${FILES[@]}")
DESCRIPTION="the database and the startup markers"
if [[ "$1" == "--keep-data" ]]; then
    REMOVE_FILES=()
    DESCRIPTION="only the startup markers"
fi

echo ""
echo "## Resetting the database"
echo ""
echo "This will remove $DESCRIPTION in $DATA_DIR."
echo ""
read -r -p "Continue? [Y/n]: " answer
if [[ ! -z "$answer" && ! "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "Aborted, nothing was changed."
    exit 1
fi

echo ""
cd "$PROJECT_DIR/$DATA_DIR"
for file in "${REMOVE_FILES[@]}" "${MARKERS[@]}"; do
    echo -n "   removing $DATA_DIR/$file ... "
    if rm -f "$file"; then
        echo "success"
    else
        echo "failed"
        exit 1
    fi
done

echo ""
echo "## Database reset."
echo ""
echo "The database is created again on the next startup of the triplestore."
