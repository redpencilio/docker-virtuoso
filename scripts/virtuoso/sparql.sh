#!/bin/bash
QUERY_FILE=$1
TRIPLESTORE=${2:-"triplestore"}
USERNAME=${3:-"dba"}
PASSWORD=${4:-"dba"}
PROJECT_DIR=/project
QUERY_PATH=data/db/queries/$QUERY_FILE

if [[ -z "$QUERY_FILE" ]]; then
    echo "file-name is a required parameter"
    exit -1
fi

if [[ ! -f "$PROJECT_DIR/$QUERY_PATH" ]]; then
    echo "ERROR: $QUERY_PATH does not exist"
    exit -1
fi

echo "Executing SPARQL query $QUERY_PATH"
isql-v -H $TRIPLESTORE -U $USERNAME -P $PASSWORD <<EOF
SPARQL
$(cat "$PROJECT_DIR/$QUERY_PATH")
;
exit;
EOF
