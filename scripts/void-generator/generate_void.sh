#!/bin/bash
SPARQL_ENDPOINT=${1:-"http://triplestore:8890/sparql"}
GRAPH=${2:-"http://mu.semte.ch/graphs/public"}
IRI_OF_VOID=${3:-"http://mu.semte.ch/.well-known/void#"}

DATE=`date +%Y%0m%0d%0H%0M%0S`
FILENAME="void_structural_metadata_${DATE}.ttl"
DIR="/project/doc/void"

mkdir -p $DIR

echo "Running VoID structural metadata generator on SPARQL endpoint $SPARQL_ENDPOINT for graph $GRAPH"
java -jar /void-generator.jar \
    -r "$SPARQL_ENDPOINT" \
    --void-file "$DIR/$FILENAME" \
    --iri-of-void "$IRI_OF_VOID" \
    -g "$GRAPH"
