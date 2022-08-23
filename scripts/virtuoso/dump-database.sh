#!/bin/bash
USERNAME=${2:-"dba"}
PASSWORD=${3:-"dba"}
TRIPLESTORE=${1:-"triplestore"}

if [[ "$#" -ge 3 ]]; then
    echo "Usage:"
    echo "   mu script triplestore [hostname] [username] [password]"
    exit -1;
fi

if [[ -d "/project/data/db" ]];then
    mkdir -p /project/data/db/dumps
else
    echo "WARNING:"
    echo "    did not find data/db folder in your project, so did not create data/db/dumps!"
    echo " "
fi


echo "connecting to $TRIPLESTORE with $USERNAME"
isql-v -H $TRIPLESTORE -U $USERNAME -P $PASSWORD <<EOF
CREATE PROCEDURE dump_nquads
  ( IN  dir                VARCHAR := 'dumps'
  , IN  start_from             INT := 1
  , IN  file_length_limit  INTEGER := 100000000
  , IN  comp                   INT := 1
  )
  {
    DECLARE  inx, ses_len  INT
  ; DECLARE  file_name     VARCHAR
  ; DECLARE  env, ses      ANY
  ;

  inx := start_from;
  SET isolation = 'uncommitted';
  env := vector (0,0,0);
  ses := string_output (10000000);
  FOR (SELECT * FROM (sparql define input:storage "" SELECT ?s ?p ?o ?g { GRAPH ?g { ?s ?p ?o } . FILTER ( ?g != virtrdf: ) } ) AS sub OPTION (loop)) DO
    {
      DECLARE EXIT HANDLER FOR SQLSTATE '22023'
	{
	  GOTO next;
	};
      http_nquad (env, "s", "p", "o", "g", ses);
      ses_len := LENGTH (ses);
      IF (ses_len >= file_length_limit)
	{
	  file_name := sprintf ('%s/output%06d.nq', dir, inx);
	  string_to_file (file_name, ses, -2);
	  IF (comp)
	    {
	      gz_compress_file (file_name, file_name||'.gz');
	      file_delete (file_name);
	    }
	  inx := inx + 1;
	  env := vector (0,0,0);
	  ses := string_output (10000000);
	}
      next:;
    }
  IF (length (ses))
    {
      file_name := sprintf ('%s/output%06d.nq', dir, inx);
      string_to_file (file_name, ses, -2);
      IF (comp)
	{
	  gz_compress_file (file_name, file_name||'.gz');
	  file_delete (file_name);
	}
      inx := inx + 1;
      env := vector (0,0,0);
    }
}
;
    dump_nquads ('dumps', 1, 100000000, 1);
    exit;
EOF
gunzip /project/data/db/dumps/*
