#!/usr/bin/env python3
import sys

target_file = "libsrc/Wi/sparql_core.c"
new_names = [
    "HTTP_CLIENT_INTERNAL",
    "HTTP_GET",
    "HTTP_PIPELINE",
    "IMAP_GET",
    "IMAP4_LOGIN",
    "IMAP4_COMMAND",
    "IMAP4_LOGOUT",
    "NNTP_GET",
    "NNTP_GET_NEW",
    "NNTP_AUTH_GET",
    "NNTP_ID_GET",
    "NNTP_POST",
    "NNTP_AUTH_POST",
    "POP3_GET",
    "SMTP_SEND",
    "LDAP_SEARCH",
    "LDAP_DELETE",
    "LDAP_ADD",
    "LDAP_MODIFY",
]

with open(target_file) as f:
    lines = f.readlines()

if any('"' + new_names[0] + '"' in line for line in lines):
    print("Already patched, skipping.")
    sys.exit(0)

# Insert into spar_unsafe_sql_names[] using brace tracking so we correctly
# find the closing } regardless of whether the array uses a NULL sentinel.
in_array = False
brace_depth = 0
inserted = False
out = []

for line in lines:
    if not in_array:
        if "static" in line and "spar_unsafe_sql_names" in line and "[" in line:
            in_array = True
            brace_depth = line.count('{') - line.count('}')
        out.append(line)
        continue

    open_count = line.count('{')
    close_count = line.count('}')
    new_depth = brace_depth + open_count - close_count

    if not inserted:
        # Insert before the NULL sentinel if present, otherwise before closing }.
        if line.strip().startswith('NULL'):
            for name in new_names:
                out.append('  "' + name + '",\n')
            inserted = True
            in_array = False
        elif new_depth <= 0:
            for name in new_names:
                out.append('  "' + name + '",\n')
            inserted = True
            in_array = False

    if new_depth <= 0:
        in_array = False

    brace_depth = new_depth
    out.append(line)

if not inserted:
    print("ERROR: spar_unsafe_sql_names array not found!")
    sys.exit(1)

with open(target_file, "w") as f:
    f.writelines(out)
print("Patched " + str(len(new_names)) + " names into spar_unsafe_sql_names.")

# Fix intentional fall-throughs in switch statements that GCC 11 flags as errors.
fallthrough_markers = ["SPART_TRIPLE_PREDICATE_IDX", "SPART_TRIPLE_SUBJECT_IDX"]
with open(target_file) as f:
    lines = f.readlines()
out = []
for line in lines:
    stripped = line.rstrip("\n")
    if (any(m in stripped for m in fallthrough_markers)
            and stripped.rstrip().endswith(");")
            and "/* falls through */" not in stripped):
        stripped = stripped.rstrip() + " /* falls through */"
        print("Added fallthrough annotation: " + stripped.strip())
    out.append(stripped + "\n")
with open(target_file, "w") as f:
    f.writelines(out)
